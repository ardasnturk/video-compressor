# Video Compressor

macOS menü çubuğunda çalışan, hızlı ve şık bir video sıkıştırıcı. Videoyu sürükle, bırak; seçtiğin formatta küçültülmüş hâli kaynağın yanına kaydedilir.

## Özellikler

- **Menü çubuğu uygulaması**: Dock'ta ikon yok, sıkıştırma sırasında menü çubuğunda canlı yüzde görünür
- **Sürükle & bırak**: dosya veya klasör bırakabilirsin. ⌘O ile dosya seçilir. Finder'da *Birlikte Aç → Video Compressor* de çalışır
- **Formatlar**: MP4, MOV, M4V, WebM, MKV, GIF
- **Codec'ler**: H.264, HEVC (donanım hızlandırmalı), AV1, VP9
- **İki sıkıştırma modu**
  - *Kalite*: En küçük → En iyi (5 seviye, piksel başına bit hesabı; kaynaktan daha yüksek bit hızı asla kullanılmaz)
  - *Hedef boyut*: "en fazla 10 MB" gibi. İlk deneme hedefi aşarsa düzeltilmiş bit hızıyla otomatik ikinci geçiş yapılır
- **Hızlı ayarlar**: Discord (10 MB), WhatsApp (16 MB), E-posta (24 MB), Web (VP9), Arşiv (HEVC), GIF
- **Gelişmiş**: çözünürlük sınırı (4K…360p, büyütme yapılmaz), FPS sınırı, sesi kaldırma
- **Kuyruk**: aynı anda 1–4 iş, tahmini çıktı boyutu, kalan süre, tasarruf yüzdesi, iptal ve yeniden deneme
- Bitmiş dosyayı satırdan doğrudan Slack/Mail/Finder'a **sürükleyebilirsin**. Çift tıklayınca açılır, sağ tıkla kopyalanır
- Bildirim, ses, Finder'da gösterme, girişte açılma, çıktı klasörü ve dosya adı eki ayarları

## Motorlar

| Motor | Ne zaman | Bağımlılık |
|---|---|---|
| AVFoundation + VideoToolbox | MP4/MOV/M4V + H.264/HEVC | Yok (yerleşik) |
| ffmpeg | WebM, MKV, GIF, AV1, VP9 ve AVFoundation'ın açamadığı kaynaklar (ör. .webm, .mkv, .avi) | `brew install ffmpeg` |

ffmpeg yoksa uygulama yine çalışır. Yalnızca o formatlarda uyarı gösterir.

## Kurulum

```bash
./scripts/build-app.sh --install
```

Bu komut `build/Video Compressor.app` dosyasını derler (Universal, ad-hoc imzalı), `/Applications` klasörüne kopyalar ve uygulamayı açar. Sadece derlemek için `--install` olmadan çalıştır.

Gereksinim: macOS 14+, Xcode / Swift 5.10+.

## Geliştirme

```bash
swift build          # derle
swift test           # uçtan uca kodlama testleri (fixture için ffmpeg gerekir)
```

Popover içeriğini normal bir pencerede açmak için (ekran görüntüsü / UI geliştirme):

```bash
open --env VC_DEBUG_WINDOW=1 --env VC_DEBUG_FILES=/yol/video.mov "build/Video Compressor.app"
```

### Yapı

```
Sources/VideoCompressor/
  App/        VideoCompressorApp (MenuBarExtra, ayarlar penceresi, AppDelegate)
  Models/     CompressionSettings (format/codec/kalite/presetler), VideoInfo + EncodePlan, CompressionJob
  Services/   JobQueue, AVFoundationEngine, FFmpegEngine, VideoProbe, FFmpegLocator, AppSettings
  Views/      MenuContentView, SettingsPanelView, DropZoneView, JobRowView, PreferencesView, Components
```
