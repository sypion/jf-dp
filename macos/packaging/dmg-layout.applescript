on run {volumeName}
	tell application "Finder"
		tell disk volumeName
			open
			tell container window
				set current view to icon view
				set toolbar visible to false
				set statusbar visible to false
				set pathbar visible to false
				-- 640 × 400 inside, under the title bar.
				set bounds to {200, 120, 840, 548}
			end tell
			set options to icon view options of container window
			set arrangement of options to not arranged
			set icon size of options to 128
			set text size of options to 13
			set shows item info of options to false
			set background picture of options to file ".background:background.tiff"
			set position of item "jf-dp.app" of container window to {170, 180}
			set position of item "Applications" of container window to {470, 180}
			try
				set position of item ".background" of container window to {170, 700}
			end try
			update without registering applications
			delay 1
			close
		end tell
	end tell
end run
