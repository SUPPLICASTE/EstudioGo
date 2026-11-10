# EstudioGo 📘

**Planifica. Organiza. Aprueba.** Aplicación académica para Android y Windows, sin registro y con almacenamiento local.

## Funciones
- Gestión de asignaturas, profesores, exámenes y notas.
- Edición y eliminación con confirmación.
- Cálculo de media aritmética y ponderada.
- Estadísticas por asignatura y resumen general.
- Calendario mensual con exámenes señalados.
- Notificaciones locales el día anterior a cada examen (requieren permiso).
- Modo claro y oscuro.
- Exportación e importación mediante QR.
- Sincronización manual por Wi-Fi local entre dos dispositivos.
- Icono propio y datos guardados en el dispositivo.

## Descargar
- **Android (APK):** [EstudioGo 2.1](https://github.com/SUPPLICASTE/EstudioGo/releases/tag/v2.1)
- **Windows:** [EstudioGo 2.2](https://github.com/SUPPLICASTE/EstudioGo/releases/tag/v2.2) (paquete ZIP portable; descomprimir y ejecutar `estudiogo.exe`).

También puedes consultar las compilaciones en la pestaña **Actions**.

## Compilar
```bash
flutter pub get
flutter build apk --release
flutter build windows --release
```
El APK se genera en `build/app/outputs/flutter-apk/app-release.apk`. La aplicación Windows se genera en `build/windows/x64/runner/Release/`.

## Limitaciones
La sincronización disponible actualmente es manual por Wi-Fi local: ambos dispositivos deben estar en la misma red y el anfitrión debe mantener la pantalla de sincronización abierta. La sincronización permanente por Internet entre Android y Windows requiere configurar un backend en la nube; todavía no está activada. Las notificaciones dependen de los permisos del dispositivo.
