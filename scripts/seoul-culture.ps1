<#
  서울 문화행사 검색 스크립트 (서울 열린데이터광장 culturalEventInfo).

  사용법
    seoul-culture.ps1 [-Keyword 재즈] [-Category 콘서트] [-Date 2026-11-01] [-Count 5]

  - 세 조건은 모두 선택이며, 함께 주면 모두 만족하는 행사만 나온다.
  - Date 는 「시작일 또는 종료일이 그날인 행사」만 찾는다 (그날 진행 중이기만 한 행사는 빠진다).
  - 인증키: 사용자 환경변수 SEOUL_API_KEY. 없으면 sample 키를 쓰고, 이때는 최대 5건.

  출력
    검색 결과 전체를 보여 준 뒤, 「----KAKAO----」 줄 아래에 카카오톡 나챗방용 메시지(200자 이내)를 붙인다.
#>
param(
  [string]$Keyword = '',
  [string]$Category = '',
  [string]$Date = '',
  [ValidateRange(1, 20)]
  [int]$Count = 5
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$KakaoLimit = 200
$SampleLimit = 5

# setx 로 등록한 값은 지금 열린 세션에 안 보이므로 사용자 환경변수 저장소에서도 읽는다.
$key = $env:SEOUL_API_KEY
if (-not $key) { $key = [Environment]::GetEnvironmentVariable('SEOUL_API_KEY', 'User') }
$isSample = -not $key
if ($isSample) {
  $key = 'sample'
  if ($Count -gt $SampleLimit) { $Count = $SampleLimit }
}

if ($Date -and $Date -notmatch '^\d{4}-\d{2}-\d{2}$') { throw "날짜 형식이 잘못됐습니다: '$Date' (예: 2026-11-01)" }

function Format-PathArg([string]$s) {
  # 빈 조건은 공백(%20)으로 채워야 다음 자리 조건이 제대로 들어간다.
  if ([string]::IsNullOrWhiteSpace($s)) { return '%20' }
  return [uri]::EscapeDataString($s.Trim())
}

$url = "http://openapi.seoul.go.kr:8088/$key/json/culturalEventInfo/1/$Count/" +
  "$(Format-PathArg $Category)/$(Format-PathArg $Keyword)/$(Format-PathArg $Date)"
$res = Invoke-RestMethod $url -TimeoutSec 20

# 조건에 맞는 행사가 없거나 키가 잘못되면 culturalEventInfo 없이 RESULT 만 온다.
if (-not $res.culturalEventInfo) {
  $code = $res.RESULT.CODE
  if ($code -eq 'INFO-200') { $total = 0; $rows = @() }
  else { throw "API 오류: $code $($res.RESULT.MESSAGE)" }
} else {
  $info = $res.culturalEventInfo
  if ($info.RESULT.CODE -ne 'INFO-000') { throw "API 오류: $($info.RESULT.CODE) $($info.RESULT.MESSAGE)" }
  $total = [int]$info.list_total_count
  $rows = @($info.row)
}

$conds = @()
if ($Keyword) { $conds += "'$Keyword'" }
if ($Category) { $conds += "분류 $Category" }
if ($Date) { $conds += "$Date 시작·종료" }
$condText = if ($conds.Count) { $conds -join ', ' } else { '전체' }

# ── 터미널용 전체 결과 ──
Write-Output "[서울 문화행사] $condText (총 ${total}건 중 $($rows.Count)건)"
if ($isSample) { Write-Output '※ sample 키 사용 중: 최대 5건만 조회됩니다.' }
$i = 0
foreach ($r in $rows) {
  $i++
  Write-Output ''
  Write-Output "$i. [$($r.CODENAME)] $($r.TITLE.Trim())"
  Write-Output "   기간: $($r.DATE) | 장소: $($r.PLACE) ($($r.GUNAME))"
  Write-Output "   요금: $($r.IS_FREE)$(if ($r.USE_FEE) { " - $($r.USE_FEE)" })"
  Write-Output "   링크: $($r.HMPG_ADDR)"
}
if ($rows.Count -eq 0) { Write-Output '조건에 맞는 행사가 없습니다.' }

# ── 카카오톡 나챗방용 메시지 (200자 이내) ──
function Format-ShortDate([string]$d) {
  # "2026-10-31~2026-10-31" → "10/31", 기간이면 "11/01~11/30"
  $parts = $d -split '~' | ForEach-Object { if ($_ -match '\d{4}-(\d{2})-(\d{2})') { "$($Matches[1])/$($Matches[2])" } }
  if ($parts.Count -eq 2 -and $parts[0] -ne $parts[1]) { return "$($parts[0])~$($parts[1])" }
  return $parts[0]
}

$header = "[서울 문화행사] $condText ${total}건"
$lines = @()
$i = 0
foreach ($r in $rows) {
  $i++
  $title = $r.TITLE.Trim()
  if ($title.Length -gt 22) { $title = $title.Substring(0, 21) + '…' }
  $lines += "$i. $title ($(Format-ShortDate $r.DATE), $($r.GUNAME))"
}
if ($rows.Count -eq 0) { $lines = @('조건에 맞는 행사가 없습니다.') }

# 넘치면 뒤에서부터 빼고, 뺀 건수를 마지막 줄에 적는다.
$kept = $lines
while ($kept.Count -gt 1) {
  $more = $lines.Count - $kept.Count
  $tail = if ($more -gt 0) { @("외 ${more}건") } else { @() }
  $msg = (@($header) + $kept + $tail) -join "`n"
  if ($msg.Length -le $KakaoLimit) { break }
  $kept = @($kept[0..($kept.Count - 2)])
}
$more = $lines.Count - $kept.Count
$tail = if ($more -gt 0) { @("외 ${more}건") } else { @() }
$msg = (@($header) + $kept + $tail) -join "`n"
if ($msg.Length -gt $KakaoLimit) { $msg = $msg.Substring(0, $KakaoLimit - 1) + '…' }

Write-Output ''
Write-Output '----KAKAO----'
Write-Output $msg
