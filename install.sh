#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "Resource Monitor derleniyor..."
./build_app.sh

echo "Kullanıcı Uygulamalarına (~/Applications/) yükleniyor..."
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Resource Monitor.app"
cp -R "Resource Monitor.app" "$HOME/Applications/"

echo "Spotlight ve LaunchServices kaydediliyor..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/Resource Monitor.app" 2>/dev/null || true

echo ""
echo " Kurulum başarıyla tamamlandı!"
echo "Artık Spotlight (⌘ Space) açıp 'Resource Monitor' yazarak dilediğiniz zaman başlatabilirsiniz."
echo "Hemen başlatmak için: open -a \"Resource Monitor\""
