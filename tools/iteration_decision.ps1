param([string]$Tool,[ValidateSet('Accept','Reject','Clip','Feedback','Review')][string]$Action,[string]$Id,[string]$Output,[int]$Seed,[int]$Point,[string]$Feedback)
$ErrorActionPreference='Stop'
try {
    $argsForReview = @{ Action=$Action; Id=$Id }
    if ($Action -eq 'Clip') {
        $argsForReview.Seed = $Seed
        $argsForReview.Point = $Point
    } elseif ($Action -eq 'Review') {
        $argsForReview.Seed = $Seed
        $argsForReview.Matches = 1
    } elseif ($Action -eq 'Feedback' -and $Feedback -ne '-') {
        $argsForReview.Note = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Feedback))
    }
    & $Tool @argsForReview | Out-Null
    $message = switch ($Action) {
        'Accept' { 'Accepted. Reopen the game to load the change.' }
        'Reject' { 'Rejected.' }
        'Clip' { 'Comparison rendered.' }
        'Review' { 'Review refreshed.' }
        'Feedback' { 'Sent back with your feedback.' }
    }
    $message | Set-Content -LiteralPath $Output -Encoding utf8
} catch {
    $_.Exception.Message | Set-Content -LiteralPath $Output -Encoding utf8
}
