cask "superopt" do
  version "0.8.0"
  sha256 "9e3ebecfa91cb0033141e593702a3316cb1f94404be6f2f354cae3ad00d9d610"

  url "https://github.com/logonoff/superopt/releases/download/#{version}/SuperOpt.zip"
  name "SuperOpt"
  desc "Remaps keyboard shortcuts among other things to make macOS feel like Linux and GNOME!"
  homepage "https://logonoff.co/superopt"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :golden_gate

  app "SuperOpt.app"

  postflight_steps do
    run "/usr/bin/xattr", args: ["-rd", "com.apple.quarantine", "{{appdir}}/SuperOpt.app"]
  end

  zap trash: "~/Library/Preferences/co.logonoff.superopt.plist"

  caveats <<~EOS
    #{token} requires Accessibility and Input Monitoring permissions.
    Grant both in System Settings > Privacy & Security after first launch.

    #{token} is not signed with an Apple Developer ID.
    The quarantine flag is removed automatically during install.
    If macOS still says the app is damaged, run:
      xattr -rd com.apple.quarantine #{appdir}/SuperOpt.app
  EOS
end
