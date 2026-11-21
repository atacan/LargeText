# Written by scripts/release/update-cask.sh on every release; edit the script, not this file.
cask "largetext" do
  version "0.1.1"
  sha256 "9f5dad9ae3c4b6ae1008ea163f1e13741c45694993c047a175709a045ac4c162"

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
