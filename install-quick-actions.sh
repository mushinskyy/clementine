#!/bin/bash
# Generates Finder Quick Actions (Automator workflows) in ~/Library/Services that hand
# the selected files to Clementine. Quick Actions appear in Finder's right-click menu
# for every file, including iCloud Drive folders such as Desktop and Documents.
set -euo pipefail
APP="${1:-/Applications/Clementine.app}"
BIN="$APP/Contents/MacOS/Clementine"
DEST="$HOME/Library/Services"
mkdir -p "$DEST"

make_action() {   # name, shell command
  local name="$1" cmd="$2"
  local wf="$DEST/$name.workflow"
  rm -rf "$wf"
  mkdir -p "$wf/Contents"
  local esc
  esc=$(printf '%s' "$cmd" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
  cat > "$wf/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSBackgroundColorName</key><string>background</string>
			<key>NSIconName</key><string>NSActionTemplate</string>
			<key>NSMenuItem</key><dict><key>default</key><string>$name</string></dict>
			<key>NSMessage</key><string>runWorkflowAsService</string>
			<key>NSRequiredContext</key><dict><key>NSApplicationIdentifier</key><string>com.apple.finder</string></dict>
			<key>NSSendFileTypes</key><array><string>public.item</string></array>
		</dict>
	</array>
</dict>
</plist>
PLIST
  cat > "$wf/Contents/document.wflow" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AMApplicationBuild</key><string>534</string>
	<key>AMApplicationVersion</key><string>2.10</string>
	<key>AMDocumentVersion</key><string>2</string>
	<key>actions</key>
	<array>
		<dict>
			<key>action</key>
			<dict>
				<key>AMAccepts</key><dict><key>Container</key><string>List</string><key>Optional</key><true/><key>Types</key><array><string>com.apple.cocoa.string</string></array></dict>
				<key>AMActionVersion</key><string>2.0.3</string>
				<key>AMApplication</key><array><string>Automator</string></array>
				<key>AMParameterProperties</key><dict><key>COMMAND_STRING</key><dict/><key>CheckedForUserDefaultShell</key><dict/><key>inputMethod</key><dict/><key>shell</key><dict/><key>source</key><dict/></dict>
				<key>AMProvides</key><dict><key>Container</key><string>List</string><key>Types</key><array><string>com.apple.cocoa.string</string></array></dict>
				<key>ActionBundlePath</key><string>/System/Library/Automator/Run Shell Script.action</string>
				<key>ActionName</key><string>Run Shell Script</string>
				<key>ActionParameters</key>
				<dict>
					<key>COMMAND_STRING</key><string>$esc</string>
					<key>CheckedForUserDefaultShell</key><true/>
					<key>inputMethod</key><integer>1</integer>
					<key>shell</key><string>/bin/zsh</string>
					<key>source</key><string></string>
				</dict>
				<key>BundleIdentifier</key><string>com.apple.RunShellScript</string>
				<key>CFBundleVersion</key><string>2.0.3</string>
				<key>CanShowSelectedItemsWhenRun</key><false/>
				<key>CanShowWhenRun</key><true/>
				<key>Category</key><array><string>AMCategoryUtilities</string></array>
				<key>Class Name</key><string>RunShellScriptAction</string>
				<key>InputUUID</key><string>$(uuidgen)</string>
				<key>Keywords</key><array><string>Shell</string><string>Script</string></array>
				<key>OutputUUID</key><string>$(uuidgen)</string>
				<key>UUID</key><string>$(uuidgen)</string>
				<key>UnlocalizedApplications</key><array><string>Automator</string></array>
				<key>arguments</key>
				<dict>
					<key>0</key><dict><key>default value</key><integer>0</integer><key>name</key><string>inputMethod</string><key>required</key><string>0</string><key>type</key><string>0</string><key>uuid</key><string>0</string></dict>
					<key>1</key><dict><key>default value</key><false/><key>name</key><string>CheckedForUserDefaultShell</string><key>required</key><string>0</string><key>type</key><string>0</string><key>uuid</key><string>1</string></dict>
					<key>2</key><dict><key>default value</key><string></string><key>name</key><string>source</string><key>required</key><string>0</string><key>type</key><string>0</string><key>uuid</key><string>2</string></dict>
					<key>3</key><dict><key>default value</key><string></string><key>name</key><string>COMMAND_STRING</string><key>required</key><string>0</string><key>type</key><string>0</string><key>uuid</key><string>3</string></dict>
					<key>4</key><dict><key>default value</key><string>/bin/sh</string><key>name</key><string>shell</string><key>required</key><string>0</string><key>type</key><string>0</string><key>uuid</key><string>4</string></dict>
				</dict>
				<key>conversionLabel</key><integer>0</integer>
				<key>isViewVisible</key><integer>1</integer>
				<key>location</key><string>309.000000:305.000000</string>
				<key>nibPath</key><string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib</string>
			</dict>
			<key>isViewVisible</key><integer>1</integer>
		</dict>
	</array>
	<key>connectors</key><dict/>
	<key>workflowMetaData</key>
	<dict>
		<key>applicationBundleID</key><string>com.apple.finder</string>
		<key>applicationBundleIDsByPath</key><dict><key>/System/Library/CoreServices/Finder.app</key><string>com.apple.finder</string></dict>
		<key>applicationPath</key><string>/System/Library/CoreServices/Finder.app</string>
		<key>applicationPaths</key><array><string>/System/Library/CoreServices/Finder.app</string></array>
		<key>inputTypeIdentifier</key><string>com.apple.Automator.fileSystemObject</string>
		<key>outputTypeIdentifier</key><string>com.apple.Automator.nothing</string>
		<key>presentationMode</key><integer>15</integer>
		<key>processesInput</key><false/>
		<key>serviceApplicationBundleID</key><string>com.apple.finder</string>
		<key>serviceApplicationPath</key><string>/System/Library/CoreServices/Finder.app</string>
		<key>serviceInputTypeIdentifier</key><string>com.apple.Automator.fileSystemObject</string>
		<key>serviceOutputTypeIdentifier</key><string>com.apple.Automator.nothing</string>
		<key>serviceProcessesInput</key><false/>
		<key>systemImageName</key><string>NSActionTemplate</string>
		<key>useAutomaticInputType</key><false/>
		<key>workflowTypeIdentifier</key><string>com.apple.Automator.servicesMenu</string>
	</dict>
</dict>
</plist>
PLIST
  echo "  • $name"
}

# Remove any earlier Clementine actions, then write the current set.
find "$DEST" -maxdepth 1 -name "Clementine*.workflow" -exec rm -rf {} +
make_action "Clementine: Convert or Process…" "\"$BIN\" --pick \"\$@\""
make_action "Clementine: Convert to PNG"      "\"$BIN\" --run convert PNG \"\$@\""
make_action "Clementine: Convert to JPG"      "\"$BIN\" --run convert JPG \"\$@\""
make_action "Clementine: Convert to PDF"      "\"$BIN\" --run convert PDF \"\$@\""
make_action "Clementine: Convert to MP4"      "\"$BIN\" --run convert MP4 \"\$@\""
make_action "Clementine: Compress"            "\"$BIN\" --run tools Compress \"\$@\""
make_action "Clementine: ZIP"                 "\"$BIN\" --run convert ZIP \"\$@\""
/System/Library/CoreServices/pbs -update 2>/dev/null || true
echo "Quick Actions installed in $DEST"
