# EstudioGo 📘

**Planifica. Organiza. Aprueba.** Planificador académico minimalista y de código abierto.

![EstudioGo](docs/estudiogo-cover.svg)

## Funciones
- Gestión de clases, profesores, exámenes y notas con edición y confirmación antes de eliminar.
- Calendario mensual con marcas en los días que tienen exámenes.
- Estadísticas y medias por asignatura.
- Recordatorios locales de exámenes el día anterior (Android).
- Tema claro y oscuro.
- Sincronización entre dispositivos por Wi-Fi local mediante QR, sin nube.
- Icono propio de EstudioGo.
- Cálculo automático de media aritmética y ponderada.
- Panel con resumen académico y próximos exámenes.
- Guardado local, sin cuenta.
- Mostrar y escanear QR para transferir datos entre dispositivos.
- Diseño adaptable a móvil y pantallas grandes.

## Ejecutar
    flutter create --platforms=android,web,windows .
    flutter pub get
    flutter run

## Generar APK
    flutter build apk --release

El APK aparece en build/app/outputs/flutter-apk/app-release.apk.

## GitHub Actions
Cada push a main compila el APK y la versión web. Descarga EstudioGo-APK o EstudioGo-Web en Actions. La versión web se puede publicar en GitHub Pages para abrirla desde el ordenador.

## QR y sincronización
La sincronización Wi-Fi se inicia desde el icono Wi-Fi: un dispositivo muestra un QR y el otro lo escanea. Ambos deben estar en la misma red y el dispositivo anfitrión debe mantener la sesión abierta. Los datos se fusionan localmente; no hay sincronización continua en segundo plano ni servidor en la nube.

## Privacidad
Los datos se guardan localmente. El QR contiene los datos exportados: no lo compartas públicamente si incluyen información personal.

## Licencia
MIT.
