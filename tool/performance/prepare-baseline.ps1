param([string]$BaselineRef = 'b8546e888d1f2ff7c057a03db0895d78ce461d50')
$ErrorActionPreference = 'Stop'
if ($BaselineRef -notmatch '^[a-f0-9]{40}$') { throw 'Use an exact baseline commit.' }
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$targetRoot = Join-Path $repoRoot '.dart_tool/sprint26-before'
New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null
$libRoot = (Join-Path $repoRoot 'lib') + [IO.Path]::DirectorySeparatorChar
function Export-BaselineSource([string]$sourcePath, [string]$fileName) {
    $lines = & git -C $repoRoot show "${BaselineRef}:$sourcePath"
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read baseline commit.' }
    $source = $lines -join "`n"
    $sourceDirectory = Split-Path (Join-Path $repoRoot $sourcePath)
    $source = [regex]::Replace($source, "import '([^']+)';", {
        param($match)
        $relative = $match.Groups[1].Value
        if ($relative.Contains(':')) { return $match.Value }
        $absolute = [IO.Path]::GetFullPath((Join-Path $sourceDirectory $relative))
        if (!$absolute.StartsWith($libRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Unexpected baseline import.'
        }
        $packagePath = $absolute.Substring($libRoot.Length).Replace('\', '/')
        return "import 'package:foundi/$packagePath';"
    })
    $source = $source.Replace('package:foundi/features/professional/presentation/professional_directory_view.dart', 'professional_directory_view.dart')
    [IO.File]::WriteAllText((Join-Path $targetRoot $fileName), $source, [Text.UTF8Encoding]::new($false))
}
Export-BaselineSource 'lib/features/requests/presentation/explorer_view.dart' 'explorer_view.dart'
Export-BaselineSource 'lib/features/professional/presentation/professional_directory_view.dart' 'professional_directory_view.dart'
$entry = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'main.dart'))
$entry = $entry.Replace('package:foundi/features/requests/presentation/explorer_view.dart', 'explorer_view.dart')
$entry = $entry.Replace('package:foundi/features/professional/presentation/professional_directory_view.dart', 'professional_directory_view.dart')
[IO.File]::WriteAllText((Join-Path $targetRoot 'main.dart'), $entry, [Text.UTF8Encoding]::new($false))
Write-Output "Baseline generated from $BaselineRef in .dart_tool/sprint26-before (two original views; synthetic repositories)."
