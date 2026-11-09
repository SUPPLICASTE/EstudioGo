# EstudioGo 📘

**Planifica. Organiza. Aprueba.** Planificador académico minimalista y de código abierto.

![EstudioGo](docs/estudiogo-cover.svg)

## Funciones
- Gestión de clases, profesores, exámenes y notas.
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
Cada push a main compila el APK. Descárgalo en Actions, dentro del artefacto EstudioGo-APK.

## QR y sincronización
Esta versión transfiere una copia de los datos mediante QR. No es sincronización automática en tiempo real ni usa la nube; para ello se necesita un backend como Firebase o Supabase.

## Privacidad
Los datos se guardan localmente. El QR contiene los datos exportados: no lo compartas públicamente si incluyen información personal.

## Licencia
MIT.
