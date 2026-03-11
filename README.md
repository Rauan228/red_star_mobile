# Red Star VPN — MVP Mobile App

Нативный VPN-клиент на Flutter + Android с движком sing-box.  
"Скачал → нажал кнопку → готово."

## Предварительные требования

### 1. Установить Flutter SDK
```powershell
# Скачать: https://docs.flutter.dev/get-started/install/windows
# Или через Chocolatey:
choco install flutter

# Проверить:
flutter doctor
```

### 2. Установить Android SDK
- Установить [Android Studio](https://developer.android.com/studio)
- Через SDK Manager установить:
  - Android SDK Platform 34
  - Android SDK Build-Tools 34
  - NDK (Side by side)
  - CMake

### 3. Установить JDK 17
```powershell
choco install openjdk17
# Или скачать: https://adoptium.net/
```

### 4. Настроить переменные среды
```powershell
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-17..."
```

## Быстрый старт

### 1. Инициализировать Flutter в проекте
```powershell
cd D:\VPN\redstar_vpn
flutter create . --org com.redstarvpn --project-name redstar_vpn --platforms android
```

> ⚠️ Если `flutter create` перезапишет файлы (например, `pubspec.yaml`, `AndroidManifest.xml`), нужно восстановить наши версии из git.

### 2. Установить зависимости
```powershell
flutter pub get
```

### 3. Получить sing-box binary

Это **самый критический шаг**. Скачать предсобранный бинарник sing-box для Android:

```powershell
# Скачать с GitHub Releases:
# https://github.com/SagerNet/sing-box/releases
# Нужен: sing-box-<version>-android-arm64.tar.gz

# Распаковать и положить бинарник сюда:
# android/app/src/main/assets/sing-box
```

**Альтернативный подход (рекомендуется для production):**

Использовать libbox — Go-библиотеку sing-box, скомпилированную для Android:

```bash
# Клонировать sing-box
git clone https://github.com/SagerNet/sing-box.git
cd sing-box

# Собрать Android library
make lib_install
make lib_android

# Скопировать AAR в проект
cp libbox.aar D:\VPN\redstar_vpn\android\app\libs\
```

Затем добавить в `android/app/build.gradle.kts`:
```kotlin
dependencies {
    implementation(files("libs/libbox.aar"))
}
```

### 4. Настроить Subscription URL

Открыть `lib/core/constants.dart` и указать рабочую Marzban subscription URL:

```dart
static const String defaultSubscriptionUrl = 'https://your-domain.com/sub/YOUR_TOKEN';
```

### 5. Собрать и запустить

```powershell
# Debug APK:
flutter build apk --debug

# Или запустить на подключённом устройстве:
flutter run
```

## Архитектура

```
Flutter UI (Dart)
    ↓ Platform Channel
Android Native (Kotlin)
    ↓ VpnBridge → SingBoxVpnService
sing-box (VPN core)
    ↓
TUN Interface → Интернет через VPN
```

## Структура проекта

```
redstar_vpn/
├── lib/
│   ├── main.dart              # Точка входа
│   ├── app.dart               # MaterialApp + тема
│   ├── core/
│   │   ├── constants.dart     # Конфиг (subscription URL)
│   │   └── vpn_status.dart    # Enum статусов
│   ├── services/
│   │   ├── vpn_service.dart   # Platform Channel bridge
│   │   └── subscription_service.dart  # Парсинг Marzban подписки
│   ├── providers/
│   │   └── vpn_provider.dart  # Riverpod state management
│   └── screens/
│       └── home_screen.dart   # Главный экран
├── android/
│   └── app/src/main/
│       ├── kotlin/com/redstarvpn/app/
│       │   ├── MainActivity.kt        # Flutter Activity
│       │   ├── VpnBridge.kt           # Flutter ↔ Android мост
│       │   └── SingBoxVpnService.kt   # VPN Service + sing-box
│       ├── AndroidManifest.xml
│       └── res/
└── pubspec.yaml
```

## Тестирование VPN

1. Установить APK на физический Android-телефон
2. Открыть приложение
3. Нажать иконку ⚙️ и ввести subscription URL (если не захардкожен)
4. Нажать большую красную кнопку
5. Разрешить VPN (системное окно)
6. Дождаться зелёной кнопки = "Подключено"
7. Открыть браузер → https://ifconfig.me → проверить IP

## FAQ

**Q: VPN не подключается?**  
A: Проверьте logcat: `adb logcat -s "SingBoxVpnService" "VpnBridge"`

**Q: sing-box binary не найден?**  
A: Убедитесь, что бинарник лежит в `android/app/src/main/assets/sing-box` и имеет правильную архитектуру (arm64).

**Q: Ошибка "VLESS конфиг не найден"?**  
A: Ваш Marzban может отдавать не VLESS конфиги. Проверьте URL в браузере — должны быть строки вида `vless://...`

## Лицензия

Private — Red Star VPN
# red_star_mobile
