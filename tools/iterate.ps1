[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Measure','Scout','Findings','ImportMarkers','New','Focus','Review','Clip','List','Accept','Reject','Feedback')]
    [string]$Action,
    [ValidatePattern('^[a-z0-9][a-z0-9-]{0,39}$')][string]$Id,
    [string]$Title,
    [string]$Note,
    [string]$ExpectedRevision,
    [ValidateRange(1,2000)][int]$Matches = 3,
    [int]$Seed = 41,
    [ValidateRange(1,100)][int]$Point = 1,
    [string]$GodotPath,
    [string]$FocusScript,
    [string[]]$FocusArguments,
    [switch]$Series,
    [switch]$DeferPublish
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$root = Join-Path $repo 'work/iterations'
$runner = Join-Path $PSScriptRoot 'iterate_matches.gd'

function Invoke-Git {
    & git -C $repo @args
    if ($LASTEXITCODE -ne 0) { throw "Git failed ($LASTEXITCODE): $args" }
}

function Write-Entry {
    $temporary = "$manifest.$PID.tmp"
    try {
        $entry | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporary -Encoding UTF8
        [IO.File]::Move($temporary, $manifest, $true)
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
    }
}

function Initialize-ReviewProject($Project, $Output) {
    $godot = Join-Path $Project '.godot'
    $stamp = Join-Path $godot 'review-import.txt'
    $cache = $null
    $lock = $null
    $projectKey = $null
    if (-not (Invoke-Git -C $Project status --porcelain -- assets project.godot scripts tools)) {
        $inputs = @((Get-FileHash -LiteralPath $GodotPath).Hash) + @(Invoke-Git -C $Project ls-tree HEAD -- assets project.godot)
        $key = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
            [Text.Encoding]::UTF8.GetBytes(($inputs -join "`n"))))
        $projectKey = $key + ((Invoke-Git -C $Project ls-tree HEAD -- scripts tools) -join "`n")
        if ((Test-Path $stamp) -and (Test-Path (Join-Path $godot 'global_script_class_cache.cfg')) -and
            (Test-Path (Join-Path $godot 'imported')) -and ([IO.File]::ReadAllText($stamp) -eq $projectKey)) { return }
        $cache = Join-Path $root ".asset-cache/$key"
        if (-not (Test-Path (Join-Path $cache 'ready'))) {
            $lock = [Threading.Mutex]::new($false, "Volleyball-assets-$key")
            try { [void]$lock.WaitOne() } catch [Threading.AbandonedMutexException] {}
        }
    }
    try {
        $originalStatus = @(Invoke-Git -C $Project status --porcelain)
        if ($cache -and (Test-Path (Join-Path $cache 'ready'))) {
            New-Item -ItemType Directory -Path $godot -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $cache 'imported') -Destination $godot -Recurse -Force
        }
        $import = Start-Process -FilePath $GodotPath -ArgumentList @('--headless','--editor','--import','--path',('"' + $Project + '"')) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $Output 'import.txt') -RedirectStandardError (Join-Path $Output 'import-errors.txt')
        $importChanges = @(Invoke-Git -C $Project status --porcelain | Where-Object { $_ -notin $originalStatus })
        $imports = @($importChanges | Where-Object { $_ -match '^ M .*\.import$' } | ForEach-Object { $_.Substring(3) })
        $uids = @($importChanges | Where-Object { $_ -match '^\?\? [a-zA-Z0-9_./-]+\.gd\.uid$' } | ForEach-Object { $_.Substring(3) })
        if ($imports.Count) { Invoke-Git -C $Project restore -- $imports }
        foreach ($uid in $uids) { Remove-Item -LiteralPath (Join-Path $Project $uid) }
        $errors = Get-Content -LiteralPath (Join-Path $Output 'import-errors.txt') -Raw
        if ($import.ExitCode -ne 0 -or $errors -match '(?m)^(SCRIPT ERROR|ERROR):') {
            throw "Godot import failed. See $Output."
        }
        if ($cache -and -not (Test-Path (Join-Path $cache 'ready'))) {
            New-Item -ItemType Directory -Path $cache -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $godot 'imported') -Destination $cache -Recurse -Force
            New-Item -ItemType File -Path (Join-Path $cache 'ready') -Force | Out-Null
        }
        if ($projectKey) { [IO.File]::WriteAllText($stamp,$projectKey) }
    } finally {
        if ($lock) {
            $lock.ReleaseMutex()
            $lock.Dispose()
        }
    }
}

function Invoke-Simulation($Project, $Result, $Count, $ReviewPoint = 0, $SimulationScript = $runner) {
    $output = Split-Path -Parent $Result
    New-Item -ItemType Directory -Path $output -Force | Out-Null
    $oldAppData = $env:APPDATA
    $env:APPDATA = Join-Path $output 'profile'
    $preferences = Join-Path $env:APPDATA 'Godot/app_userdata/Volleyball'
    New-Item -ItemType Directory -Path $preferences -Force | Out-Null
    @"
[match]
MatchAttackVertical=40.0
MatchBlockVertical=25.0
MatchServeVertical=30.0
MatchSpikeStrength=75.0
MatchPassingSkill=55.0
MatchSettingSkill=65.0
sound=false
replay_speed=0.5
"@ | Set-Content -LiteralPath (Join-Path $preferences 'match_settings.cfg')
    try {
        Initialize-ReviewProject $Project $output
        $arguments = @('--path',('"' + $Project + '"'),'--script',('"' + $SimulationScript + '"'),'--',('"' + $Result + '"'),$Seed,$Count,$ReviewPoint)
        if ($Series) { $arguments += 'series' }
        if ($ReviewPoint -eq 0) { $arguments = @('--headless') + $arguments }
        else { $arguments = @('--resolution','1200x800') + $arguments }
        $run = Start-Process -FilePath $GodotPath -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $output 'godot.txt') -RedirectStandardError (Join-Path $output 'godot-errors.txt')
        $errors = Get-Content -LiteralPath (Join-Path $output 'godot-errors.txt') -Raw
        if ($run.ExitCode -ne 0 -or $errors -match '(?m)^(SCRIPT ERROR|ERROR):' -or -not (Test-Path -LiteralPath $Result)) {
            throw "Simulation failed or timed out. See $output."
        }
    } finally { $env:APPDATA = $oldAppData }
}

function Read-Totals($Path) {
    $report = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $totals = [ordered]@{ matches = $report.matches.Count; rallies = 0; review_flags = 0 }
    foreach ($match in $report.matches) {
        $totals.rallies += $match.rallies.Count
        $totals.review_flags += $match.review_flags.Count
        foreach ($count in $match.counts.PSObject.Properties) {
            if (-not $totals.Contains($count.Name)) { $totals[$count.Name] = 0 }
            $totals[$count.Name] += $count.Value
        }
    }
    return $totals
}

function Export-DemoFindings($Result) {
    $output = Split-Path -Parent $Result
    New-Item -ItemType Directory -Path $output -Force | Out-Null
    $reader = Join-Path $PSScriptRoot 'demo_findings.gd'
    $arguments = @('--headless','--path',('"' + $repo + '"'),'--script',('"' + $reader + '"'),'--',('"' + $Result + '"'))
    $errors = Join-Path $output 'demo-findings-errors.txt'
    $run = Start-Process -FilePath $GodotPath -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru -RedirectStandardError $errors
    if ($run.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $Result)) {
        throw "Could not read Demo Match findings. See $errors."
    }
}

function Import-PlayerMarkers {
    $profile = Join-Path $env:APPDATA 'Godot/app_userdata/Volleyball'
    $traces = Join-Path $profile 'debug/setting'
    if (-not (Test-Path -LiteralPath $traces)) { return }
    $markers = Join-Path $profile 'iteration_lab/player-markers'
    New-Item -ItemType Directory -Path $markers -Force | Out-Null
    $count = 0
    $rg = Get-Command rg -ErrorAction SilentlyContinue
    $traceHits = if ($rg) {
        $context = [System.Collections.Generic.Queue[string]]::new()
        & $rg.Source --json -B 20 -F 'player_marker' -g '*.jsonl' -- $traces | ForEach-Object {
            $row = $_ | ConvertFrom-Json
            if ($row.type -eq 'begin') { $context.Clear() }
            if ($row.type -eq 'match') {
                [pscustomobject]@{Path=$row.data.path.text; Line=$row.data.lines.text; Before=$context.ToArray()}
            }
            if ($row.type -in @('context','match')) {
                $context.Enqueue($row.data.lines.text)
                if ($context.Count -gt 20) { $null=$context.Dequeue() }
            }
        }
        if ($LASTEXITCODE -gt 1) { throw "Reading debug traces failed ($LASTEXITCODE)." }
    } else {
        Get-ChildItem -LiteralPath $traces -Filter '*.jsonl' | Select-String -SimpleMatch 'player_marker' -Context 20,0 |
            ForEach-Object { [pscustomobject]@{Path=$_.Path; Line=$_.Line; Before=$_.Context.PreContext} }
    }
    foreach ($match in $traceHits) {
        try { $event = $match.Line | ConvertFrom-Json } catch { continue }
        if ($event.event -ne 'player_marker') { continue }
        $stem = [IO.Path]::GetFileNameWithoutExtension($match.Path)
        $path = Join-Path $markers "$stem-$($event.session_ms)-$($event.feed).json"
        if ((Test-Path -LiteralPath $path) -and ((Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).PSObject.Properties.Name -contains 'context')) { continue }
        $before = foreach ($line in $match.Before) {
            try { $line | ConvertFrom-Json } catch { continue }
        }
        $temporary = "$path.$PID.tmp"
        $data = @{trace=$match.Path; marker=$event; context=@($before)} | ConvertTo-Json -Depth 30 -Compress
        [IO.File]::WriteAllText($temporary,$data)
        Move-Item -LiteralPath $temporary -Destination $path -Force
        $count++
    }
    Write-Output "$count historical player markers imported."
}

if ($Action -eq 'ImportMarkers') {
    Import-PlayerMarkers
    return
}

if ($Action -eq 'List') {
    Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $path = Join-Path $_.FullName 'proposal.json'
        if (Test-Path -LiteralPath $path) { Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
    } | Select-Object id,status,title,base,candidate,note
    return
}

if ($Action -in @('Measure','Scout','Findings','Focus','Review','Clip')) {
    if (-not $GodotPath) { $GodotPath = Join-Path $repo '../game/tools/Godot_v4.6-stable_win64.exe' }
    $GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
}
if ($Action -eq 'Findings') {
    $result = Join-Path $root 'demo-findings.json'
    Export-DemoFindings $result
    Write-Output $result
    return
}
if ($Action -in @('Measure','Scout')) {
    $name = $Action.ToLowerInvariant() + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
    $result = Join-Path $root "$name/matches.json"
    Invoke-Simulation $repo $result $Matches
    Read-Totals $result
    Write-Output $result
    if ($Action -eq 'Scout') {
        $report = Get-Content -LiteralPath $result -Raw | ConvertFrom-Json
        $demoReport = Join-Path (Split-Path -Parent $result) 'demo-findings.json'
        Export-DemoFindings $demoReport
        $live = Get-Content -LiteralPath $demoReport -Raw | ConvertFrom-Json
        $simulated = foreach ($match in $report.matches) {
            foreach ($flag in $match.review_flags) {
                $priority = if ($flag.category -eq 'animation') { 1 } else { 2 }
                [pscustomobject]@{ source='simulation'; priority=$priority; match_id="seed:$($match.seed)"; seed=$match.seed; point=$flag.point; time=$flag.time; type=$flag.type; evidence=$flag }
            }
        }
        $findings = @($simulated | Where-Object { $_ }) + @($live.findings | Where-Object { $_ })
        $leads = @($findings | Group-Object -Property type | ForEach-Object {
            $examples = @($_.Group | Sort-Object -Property @{ Expression={
                if ($null -ne $_.evidence.margin_m) { $_.evidence.margin_m }
                elseif ($null -ne $_.evidence.distance_m) { $_.evidence.distance_m }
                else { 0 }
            } } | Select-Object -First 3)
            $nextCheck = $examples[0].evidence.review
            if (-not $nextCheck) {
                $nextCheck = switch -Wildcard ($_.Name) {
                    'close attempted dig' { 'Replay the approach and platform alignment just before contact.' }
                    '*without an attempt' { 'Check receiver assignment and whether the player could have committed earlier.' }
                    'ball stayed still*' { 'Inspect the preceding contact and ball-flight transition.' }
                    default { 'Inspect the flagged frame before proposing a change.' }
                }
            }
            [pscustomobject]@{ type=$_.Name; priority=($_.Group.priority | Measure-Object -Minimum).Minimum; occurrences=$_.Count; matches=@($_.Group.match_id | Where-Object { $_ } | Sort-Object -Unique).Count; review=$nextCheck; examples=$examples }
        } | Sort-Object -Property priority,@{Expression='occurrences';Descending=$true})
        $scouting = Join-Path (Split-Path -Parent $result) 'scouting.json'
        ConvertTo-Json -InputObject $leads -Depth 10 | Set-Content -LiteralPath $scouting -Encoding UTF8
        Write-Output $scouting
    }
    return
}

if (-not $Id) { throw 'Specify a proposal ID.' }
$directory = Join-Path $root $Id
$manifest = Join-Path $directory 'proposal.json'
$baseline = Join-Path $directory 'baseline'
$candidate = Join-Path $directory 'candidate'
$branch = "iteration/$Id"

if ($Action -eq 'New') {
    if (-not $Title) { throw 'Specify a title for the proposal.' }
    if (Test-Path -LiteralPath $directory) { throw "Proposal already exists: $Id" }
    $base = Invoke-Git rev-parse HEAD
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    Invoke-Git worktree add -b $branch $candidate $base
    $entry = [ordered]@{ id = $Id; title = $Title; note = $Note; base = $base; candidate = $null; status = 'draft' }
    Write-Entry
    Write-Output $candidate
    return
}

$entry = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
if ($ExpectedRevision -and ($entry.status -ne 'pending' -or $entry.candidate -ne $ExpectedRevision)) {
    throw [InvalidOperationException]::new('ProposalChanged')
}
if ($entry.status -in @('accepted','rejected')) { throw "Proposal is already $($entry.status)." }
if ($Action -eq 'Feedback') {
    if (-not $Note) { throw 'Enter feedback before sending the proposal back.' }
    $entry.note = $Note
    $entry.status = 'draft'
    Write-Entry
    return
}
if ($Action -eq 'Reject') {
    $entry.status = 'rejected'
    if ($Note) { $entry.note = $Note }
    Write-Entry
    return
}

$revision = Invoke-Git -C $candidate rev-parse HEAD
if ((Invoke-Git -C $candidate status --porcelain) -or $revision -eq $entry.base) {
    throw 'Commit the proposal changes in its worktree first.'
}
Invoke-Git merge-base --is-ancestor $entry.base $revision

if ($Action -eq 'Accept') {
    if ($entry.status -ne 'pending' -or $entry.candidate -ne $revision) { throw 'Review this exact revision before accepting.' }
    if (Invoke-Git status --porcelain) { throw 'Finish or save the local edits before accepting.' }
    $live = Invoke-Git rev-parse HEAD
    if ($live -eq $entry.base) {
        Invoke-Git merge --ff-only $revision
    } else {
        $changed = @(Invoke-Git diff --name-only $entry.base $live)
        $overlap = @(Invoke-Git diff --name-only $entry.base $revision | Where-Object { $_ -in $changed })
        if ($overlap.Count) {
            $entry.status = 'needs_review'
            Write-Entry
            throw [InvalidOperationException]::new('ProposalNeedsReview')
        }
        Invoke-Git cherry-pick "$($entry.base)..$revision"
    }
    $entry.status = 'accepted'
    if ($Note) { $entry.note = $Note }
    Write-Entry
    return
}

if ($Action -eq 'Review') {
    $live = Invoke-Git rev-parse HEAD
    $changed = @(Invoke-Git diff --name-only $entry.base $live)
    $overlap = @(Invoke-Git diff --name-only $entry.base $revision | Where-Object { $_ -in $changed })
    if ($live -ne $entry.base -and $overlap.Count) {
        try {
            Invoke-Git -C $candidate rebase --onto $live $entry.base
        } catch {
            Invoke-Git -C $candidate rebase --abort
            throw 'The proposal conflicts with the live build and needs to be updated before review.'
        }
        $entry.base = $live
        $entry.candidate = $null
        $entry.status = 'draft'
        $revision = Invoke-Git -C $candidate rev-parse HEAD
        Write-Entry
    }
}
if (Test-Path -LiteralPath $baseline) {
    if ((Invoke-Git -C $baseline rev-parse HEAD) -ne $entry.base) {
        $baseline = Join-Path $directory ('baseline-' + $entry.base.Substring(0,12))
    }
}
if ($Action -eq 'Focus') {
    if (-not $FocusScript) { throw 'Specify -FocusScript for the focused check.' }
    $fixture = (Resolve-Path -LiteralPath $FocusScript).Path
    if (-not (Test-Path -LiteralPath $baseline)) { Invoke-Git worktree add --detach $baseline $entry.base }
    $focus = Join-Path $directory "focus-$($revision.Substring(0,12))"
    $previousProfile = $env:APPDATA
    try {
        foreach ($side in 'before','after') {
            $project = if ($side -eq 'before') { $baseline } else { $candidate }
            $output = Join-Path $focus $side
            New-Item -ItemType Directory -Path $output -Force | Out-Null
            $env:APPDATA = Join-Path $output 'profile'
            Initialize-ReviewProject $project $output
            $preview = Join-Path $output 'preview'
            $arguments = @('--headless','--path',('"' + $project + '"'),'--script',('"' + $fixture + '"'),'--')
            $inputs = if ($FocusArguments) { $FocusArguments } else { @('{output}') }
            foreach ($input_ in $inputs) { $arguments += ('"' + $input_.Replace('{output}',$preview) + '"') }
            $clock = [Diagnostics.Stopwatch]::StartNew()
            $run = Start-Process $GodotPath -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $output 'check.txt') -RedirectStandardError (Join-Path $output 'errors.txt')
            if (-not $run.WaitForExit(90000)) {
                $run.Kill()
                $run.WaitForExit()
                throw "Focused check timed out. See $output."
            }
            "$side focused check: $([math]::Round($clock.Elapsed.TotalSeconds,2)) seconds"
            Get-Content -LiteralPath (Join-Path $output 'check.txt')
            $errors = Get-Content -LiteralPath (Join-Path $output 'errors.txt') -Raw
            if ($run.ExitCode -ne 0 -or ($errors -and [regex]::IsMatch($errors,'(?m)^(SCRIPT ERROR|ERROR):'))) {
                throw "Focused check failed. See $output."
            }
        }
    } finally { $env:APPDATA = $previousProfile }
    return
}
if ($Action -eq 'Clip') {
    if (-not (Test-Path -LiteralPath $baseline)) { Invoke-Git worktree add --detach $baseline $entry.base }
    $clip = Join-Path $directory "clips/$($revision.Substring(0,12))/seed-$Seed-point-$Point"
    Invoke-Simulation $baseline (Join-Path $clip 'before/matches.json') 1 $Point
    Invoke-Simulation $candidate (Join-Path $clip 'after/matches.json') 1 $Point
    Get-ChildItem -LiteralPath $clip -Recurse -Filter '*.png' | Select-Object -ExpandProperty FullName
    return
}

$review = Join-Path $directory ('review-' + $revision.Substring(0,12))
$before = Join-Path $review 'before/matches.json'
$after = Join-Path $review 'after/matches.json'
$candidateRunner = $runner
if ('tools/iterate_matches.gd' -in @(Invoke-Git diff --name-only $entry.base $revision)) {
    $candidateRunner = Join-Path $candidate 'tools/iterate_matches.gd'
}
# Separate PowerShell processes keep the two simulations' APPDATA profiles isolated.
$runnerHash = (Get-FileHash -LiteralPath $runner).Hash
$engineHash = (Get-FileHash -LiteralPath $GodotPath).Hash
$cacheInputs = @($entry.base, $runnerHash, $engineHash, $Seed, $Matches, $Series.IsPresent, ${function:Invoke-Simulation}.ToString())
$cacheKey = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
    [Text.Encoding]::UTF8.GetBytes(($cacheInputs -join "`n"))))
$cacheDir = Join-Path $root '.review-cache'
$cachedBefore = Join-Path $cacheDir "$cacheKey.json"
$baselineJob = $null
if (Test-Path -LiteralPath $cachedBefore) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $before) -Force | Out-Null
    Copy-Item -LiteralPath $cachedBefore -Destination $before
} else {
    $baselineJob = Start-Job -ScriptBlock {
        param($GitFunction,$ImportFunction,$SimulationFunction,$Project,$Result,$Count,$RunnerPath,$Executable,$FirstSeed,$UseSeries,$RepoPath,$Base,$CacheFile,$Key,$ReviewRoot)
        $ErrorActionPreference = 'Stop'
        ${function:Invoke-Git} = [scriptblock]::Create($GitFunction)
        ${function:Initialize-ReviewProject} = [scriptblock]::Create($ImportFunction)
        ${function:Invoke-Simulation} = [scriptblock]::Create($SimulationFunction)
        $runner = $RunnerPath
        $GodotPath = $Executable
        $Seed = $FirstSeed
        $Series = $UseSeries
        $repo = $RepoPath
        $root = $ReviewRoot
        $lock = [Threading.Mutex]::new($false, "Volleyball-review-$Key")
        try {
            try { [void]$lock.WaitOne() } catch [Threading.AbandonedMutexException] {}
            try {
                if (Test-Path -LiteralPath $CacheFile) {
                    New-Item -ItemType Directory -Path (Split-Path -Parent $Result) -Force | Out-Null
                    Copy-Item -LiteralPath $CacheFile -Destination $Result
                    return
                }
                if (-not (Test-Path -LiteralPath $Project)) {
                    Invoke-Git worktree add --detach $Project $Base 2>&1 | Out-Null
                }
                Invoke-Simulation $Project $Result $Count
                New-Item -ItemType Directory -Path (Split-Path -Parent $CacheFile) -Force | Out-Null
                $cacheTemp = "$CacheFile.$PID.tmp"
                try {
                    Copy-Item -LiteralPath $Result -Destination $cacheTemp
                    [IO.File]::Move($cacheTemp, $CacheFile, $true)
                } finally {
                    if (Test-Path -LiteralPath $cacheTemp) { Remove-Item -LiteralPath $cacheTemp }
                }
            } finally {
                $lock.ReleaseMutex()
            }
        } finally {
            $lock.Dispose()
        }
    } -ArgumentList ${function:Invoke-Git}.ToString(),${function:Initialize-ReviewProject}.ToString(),${function:Invoke-Simulation}.ToString(),$baseline,$before,$Matches,$runner,$GodotPath,$Seed,$Series.IsPresent,$repo,$entry.base,$cachedBefore,$cacheKey,$root
}
try {
    Invoke-Simulation $candidate $after $Matches 0 $candidateRunner
    if ($baselineJob) {
        Receive-Job -Job $baselineJob -Wait -ErrorAction Stop
    }
} finally {
    if ($baselineJob) {
        Wait-Job -Job $baselineJob | Out-Null
        Remove-Job -Job $baselineJob
    }
}
$comparison = [ordered]@{ base = $entry.base; candidate = $revision; first_seed = $Seed; before = Read-Totals $before; after = Read-Totals $after }
$comparison | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $review 'comparison.json') -Encoding UTF8
Invoke-Git diff $entry.base $revision | Set-Content -LiteralPath (Join-Path $review 'changes.diff') -Encoding UTF8
$entry.candidate = $revision
$entry.status = if ($DeferPublish) { 'needs_review' } else { 'pending' }
Write-Entry
Write-Output $review
