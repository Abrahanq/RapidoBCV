# RápidoBCV - Publicación en Play Store

Este proyecto ya está preparado para compilar Android en formato `.aab` y subirlo a Play Console.

## 1) Firmado de release (una sola vez)

1. Crea tu keystore (upload key):

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

2. Crea el archivo `android/key.properties` con este contenido:

```properties
storePassword=TU_STORE_PASSWORD
keyPassword=TU_KEY_PASSWORD
keyAlias=upload
storeFile=../upload-keystore.jks
```

> `android/key.properties` y los archivos `.jks` están ignorados por git.

## 2) Subir versión

Antes de cada release, incrementa versión en `pubspec.yaml`:

```yaml
version: 1.0.1+2
```

- `1.0.1` = versión visible en tienda
- `+2` = `versionCode` (debe aumentar siempre)

## 3) Compilar AAB

```bash
flutter clean
flutter pub get
flutter build appbundle --release
```

Salida:

`build/app/outputs/bundle/release/app-release.aab`

## 4) Subida en Play Console

1. App > Testing interno o Producción
2. Create new release
3. Subir `app-release.aab`
4. Escribir notas de la versión
5. Review y Rollout

## Configuración Android actual

- `applicationId`: `com.rapidobcv.app`
- `namespace`: `com.rapidobcv.app`
