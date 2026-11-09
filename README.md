# EstudioGo 📘

**Planifica. Organiza. Aprueba.** Aplicación académica para Android, sin registro y con almacenamiento local.

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
En GitHub abre **Actions**, entra en la última ejecución completada correctamente y descarga el artefacto **EstudioGo-APK**. Dentro está el APK instalable.

## Compilar
```bash
flutter pub get
flutter build apk --release
```
El APK se genera en `build/app/outputs/flutter-apk/app-release.apk`.

## Limitaciones
La sincronización Wi-Fi es manual: ambos dispositivos deben estar en la misma red y el anfitrión debe mantener la pantalla de sincronización abierta. No hay cuenta ni nube. Las notificaciones dependen de los permisos del teléfono.
