# Written by scripts/release/update-cask.sh on every release; edit the script, not this file.
cask "largetext" do
  version "0.1.0"
  sha256 "8d50af3a8db88a4dc055c8107fd620692b585917b5385b77ca55f552f8903d4d"

  url "https://github.com/atacan/LargeText/releases/download/v#{version}/LargeText-#{version}.dmg"
  name "LargeText"
  desc "Type and read text in a huge overlay from any app"
  homepage "https://github.com/atacan/LargeText"

  livecheck do
    url "https://github.com/atacan/LargeText/releases/latest/download/appcast.xml"
    strategy :sparkle, &:short_version
  end

  # Sparkle updates the app in place, so `brew upgrade` leaves it alone.
  auto_updates true
  depends_on macos: ">= :sonoma"

  app "LargeText.app"

  zap trash: [
    "~/Library/Caches/com.actondon.LargeText",
    "~/Library/HTTPStorages/com.actondon.LargeText",
    "~/Library/Preferences/com.actondon.LargeText.plist",
    "~/Library/Saved Application State/com.actondon.LargeText.savedState",
  ]
end
