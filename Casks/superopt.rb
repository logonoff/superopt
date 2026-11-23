cask "superopt" do
  version "27.2.0"
  sha256 "1442e70ae291b485073b4910c8205622be449ea3e587d48b490cf992ad9d5c14"

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
    SuperOpt requires two permissions:
      Device Control and Data Access
      Input Monitoring
    Turn both on in System Settings > Privacy & Security the first time you open SuperOpt.

    SuperOpt isn’t signed with a Developer ID certificate.
    The Homebrew cask removes the quarantine attribute automatically.
    If macOS still says the app is damaged, run:
      xattr -rd com.apple.quarantine #{appdir}/SuperOpt.app
  EOS
end
