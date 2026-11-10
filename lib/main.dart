import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'sync_service_stub.dart' if (dart.library.io) 'sync_service_io.dart';

const blue = Color(0xFF2563EB);
final notifications = FlutterLocalNotificationsPlugin();
Future<void> initNotifications() async {
  tz.initializeTimeZones();
  try { final zone = await FlutterTimezone.getLocalTimezone(); tz.setLocalLocation(tz.getLocation(zone)); } catch (_) { tz.setLocalLocation(tz.getLocation('Europe/Madrid')); }
  await notifications.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
  await notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
}
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // En versiones release Flutter suele mostrar solo un bloque gris cuando
  // falla un widget. Mostrar el error concreto para poder diagnosticarlo.
  ErrorWidget.builder = (FlutterErrorDetails details) => Material(
    color: const Color(0xFFFFF1F2),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: SelectableText(
          'ESTUDIOGO NO PUDO MOSTRAR LA PANTALLA\\n\\n'
          '${details.exceptionAsString()}\\n\\n'
          'Haz una captura de este mensaje y envíala para corregir el error.',
          style: const TextStyle(color: Color(0xFF991B1B), fontSize: 16),
        ),
      ),
    ),
  );
  runApp(const EstudioGo());
}

class EstudioGo extends StatefulWidget {
  const EstudioGo({super.key});
  @override State<EstudioGo> createState() => _EstudioGoState();
}
class _EstudioGoState extends State<EstudioGo> {
  bool dark = false;
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'EstudioGo', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: blue), scaffoldBackgroundColor: const Color(0xFFF6F8FC)),
    darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark, colorScheme: ColorScheme.fromSeed(seedColor: blue, brightness: Brightness.dark)),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: Planner(dark: dark, onThemeChanged: (v) => setState(() => dark = v)));
}

class Planner extends StatefulWidget {
  final bool dark;
  final ValueChanged<bool> onThemeChanged;
  const Planner({super.key, required this.dark, required this.onThemeChanged});
  @override State<Planner> createState() => _PlannerState();
}
class _PlannerState extends State<Planner> {
  int tab = 0;
  bool loading = false; // La interfaz se muestra inmediatamente; los datos se cargan en segundo plano.
  String criterion = 'Media aritmética';
  double criterionMin = 0;
  double criterionMax = 10;
  final classes = <Map<String,dynamic>>[];
  final teachers = <Map<String,dynamic>>[];
  final exams = <Map<String,dynamic>>[];
  final grades = <Map<String,dynamic>>[];

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      void read(String key, List<Map<String,dynamic>> target) {
        try {
          final raw = p.getString(key);
          if (raw == null || raw.isEmpty) return;
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map) target.add(Map<String,dynamic>.from(item));
            }
          }
        } catch (_) {
          // Una sección dañada no debe impedir que se abra la aplicación.
        }
      }
      read('classes', classes);
      read('teachers', teachers);
      read('exams', exams);
      read('grades', grades);
      criterion = p.getString('criterion') ?? criterion;
      criterionMin = p.getDouble('criterionMin') ?? criterionMin;
      criterionMax = p.getDouble('criterionMax') ?? criterionMax;
    } catch (_) {
      // Si el almacenamiento de Windows falla, abrir la app igualmente.
    }
    // Mostrar la aplicación sin esperar a que Android inicialice las notificaciones.
    if (mounted) setState(() => loading = false);
    // Los recordatorios se preparan en segundo plano para evitar quedarse en gris
    // si el sistema tarda o bloquea la inicialización de notificaciones.
    try {
      await initNotifications();
      await _scheduleExamReminders();
    } catch (_) {
      // La aplicación sigue funcionando aunque fallen las notificaciones.
    }
  }
  Future<void> _scheduleExamReminders() async {
    await notifications.cancelAll();
    for (int i=0; i<exams.length; i++) {
      final exam=exams[i]; final examDate=DateTime.parse(exam['date']).toLocal();
      final reminder=DateTime(examDate.year,examDate.month,examDate.day).subtract(const Duration(days:1)).add(const Duration(hours:9));
      if (!reminder.isAfter(DateTime.now())) continue;
      await notifications.zonedSchedule(i+1, 'Examen mañana: ${exam['name']}', 'Asignatura: ${exam['subject']}', tz.TZDateTime.from(reminder,tz.local), const NotificationDetails(android:AndroidNotificationDetails('exam_reminders','Recordatorios de exámenes',channelDescription:'Avisos el día anterior a cada examen',importance:Importance.high,priority:Priority.high)), androidScheduleMode:AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }
  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('classes', jsonEncode(classes));
    await p.setString('teachers', jsonEncode(teachers));
    await p.setString('exams', jsonEncode(exams));
    await p.setString('grades', jsonEncode(grades));
    await p.setString('criterion', criterion);
    await p.setDouble('criterionMin', criterionMin);
    await p.setDouble('criterionMax', criterionMax);
    try { await _scheduleExamReminders(); } catch (_) {}
  }
  double? _average([String? subject]) {
    final items = grades.where((g) => subject == null || g['subject'] == subject).toList();
    if (items.isEmpty) return null;
    if (criterion == 'Media ponderada') {
      double sum = 0, weights = 0;
      for (final g in items) {
        final w = (g['weight'] as num?)?.toDouble() ?? 1;
        sum += (g['value'] as num).toDouble() * w; weights += w;
      }
      return weights == 0 ? null : sum / weights;
    }
    return items.fold<double>(0, (s,g) => s + (g['value'] as num).toDouble()) / items.length;
  }

  Future<void> _add(String kind, [int? editIndex]) async {
    final target = kind == 'classes' ? classes : kind == 'teachers' ? teachers : kind == 'exams' ? exams : grades;
    final old = editIndex == null ? null : target[editIndex];
    final name = TextEditingController(text: old == null ? '' : old['name']?.toString() ?? '');
    final extra = TextEditingController(text: old == null ? '' : kind == 'teachers' ? old['contact']?.toString() ?? '' : kind == 'grades' ? old['weight']?.toString() ?? '' : '');
    final val = TextEditingController(text: old == null ? '' : old['value']?.toString() ?? '');
    String? subject = old?['subject']?.toString();
    DateTime date = old?['date'] == null ? DateTime.now() : DateTime.parse(old!['date']);
    final classSchedules = <Map<String,String>>[];
    if (old != null && old['schedule'] is List) {
      for (final entry in old['schedule']) {
        if (entry is Map) classSchedules.add({
          'day': entry['day']?.toString() ?? '',
          'time': entry['time']?.toString() ?? '08:00',
        });
      }
    } else if (old != null && (old['day']?.toString().isNotEmpty ?? false)) {
      // Compatibilidad con asignaturas creadas en versiones anteriores.
      classSchedules.add({'day': old['day'].toString(), 'time': old['time']?.toString() ?? '08:00'});
    }
    if (kind == 'classes' && classSchedules.isEmpty) classSchedules.add({'day':'', 'time':'08:00'});
    String? classTeacher = old?['teacher']?.toString();
    final isTeacher = kind == 'teachers', isExam = kind == 'exams', isGrade = kind == 'grades';
    final result = await showDialog<Map<String,dynamic>>(context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
        title: Text(editIndex == null ? {'classes':'Nueva clase','teachers':'Nuevo profesor','exams':'Nuevo examen','grades':'Nueva nota'}[kind]! : 'Editar elemento'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: InputDecoration(labelText: isGrade ? 'Descripción' : isExam ? 'Nombre del examen' : isTeacher ? 'Nombre del profesor' : 'Asignatura')),
          if (isTeacher) TextField(controller: extra, decoration: const InputDecoration(labelText: 'Correo o contacto')),
          if (kind == 'classes') ...[
            const Align(alignment:Alignment.centerLeft,child:Text('Días y horarios',style:TextStyle(fontWeight:FontWeight.w600))),
            ...classSchedules.asMap().entries.map((entry) {
              final index = entry.key;
              final slot = entry.value;
              final currentDay = slot['day']!.isEmpty ? null : slot['day'];
              return Padding(padding:const EdgeInsets.only(top:8),child:Row(children:[
                Expanded(flex:3,child:DropdownButtonFormField<String>(
                  initialValue:currentDay,
                  isExpanded:true,
                  decoration:const InputDecoration(labelText:'Día'),
                  items:['Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo'].map((d)=>DropdownMenuItem(value:d,child:Text(d))).toList(),
                  onChanged:(v)=>refresh(() { if(v!=null) slot['day']=v; }))),
                const SizedBox(width:8),
                Expanded(flex:2,child:OutlinedButton(
                  onPressed:() async {
                    final parts=slot['time']!.split(':');
                    final picked=await showTimePicker(context:ctx,initialTime:TimeOfDay(hour:int.tryParse(parts[0])??8,minute:int.tryParse(parts.length>1?parts[1]:'0')??0));
                    if(picked!=null) refresh(()=>slot['time']='${picked.hour.toString().padLeft(2,'0')}:${picked.minute.toString().padLeft(2,'0')}');
                  },
                  child:Text(slot['time']!))),
                IconButton(tooltip:'Quitar horario',onPressed:()=>refresh(()=>classSchedules.removeAt(index)),icon:const Icon(Icons.remove_circle_outline)),
              ]));
            }),
            Align(alignment:Alignment.centerLeft,child:TextButton.icon(
              onPressed:()=>refresh(()=>classSchedules.add({'day':'','time':'08:00'})),
              icon:const Icon(Icons.add),label:const Text('Añadir otro día'))),
            DropdownButtonFormField<String>(
              initialValue: classTeacher,
              decoration: const InputDecoration(labelText: 'Profesor'),
              items: teachers.map((t) => DropdownMenuItem(value:t['name'].toString(), child:Text(t['name'].toString()))).toList(),
              onChanged: (v) => refresh(() => classTeacher = v)),
          ],
          if (isExam || isGrade) DropdownButtonFormField<String>(
            initialValue: subject,
            decoration: const InputDecoration(labelText: 'Asignatura'),
            items: classes.map((c) => DropdownMenuItem(value: c['name'] as String, child: Text(c['name'] as String))).toList(),
            onChanged: (v) => refresh(() => subject = v)),
          if (isGrade) ...[
            TextField(controller: val, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Nota ($criterionMin–$criterionMax)')),
            TextField(controller: extra, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Peso (%)')),
          ],
          if (isExam) OutlinedButton(onPressed: () async {
            final d = await showDatePicker(context: ctx, firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now().add(const Duration(days: 1500)), initialDate: date);
            if (d != null) refresh(() => date = d);
          }, child: Text(DateFormat('dd/MM/yyyy').format(date))),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () {
            if (name.text.trim().isEmpty || ((isExam || isGrade) && subject == null)) return;
            final item = <String,dynamic>{'name': name.text.trim()};
            if (isTeacher) item['contact'] = extra.text;
            if (kind == 'classes') {
              final validSchedules = classSchedules.where((slot)=>slot['day']!.isNotEmpty).toList();
              final usedDays = validSchedules.map((slot)=>slot['day']).toSet();
              if (validSchedules.isEmpty || usedDays.length != validSchedules.length) return;
              item.addAll({'schedule':validSchedules,'day':validSchedules.first['day'],'time':validSchedules.first['time'],'teacher':classTeacher ?? ''});
            }
            if (isExam) item.addAll({'subject':subject,'date':date.toIso8601String()});
            if (isGrade) {
              final n = double.tryParse(val.text.replaceAll(',', '.'));
              if (n == null || n < criterionMin || n > criterionMax) return;
              item.addAll({'subject':subject,'value':n,'weight':double.tryParse(extra.text) ?? 1});
            }
            Navigator.pop(ctx, item);
          }, child: const Text('Guardar')),
        ],
      )));
    if (result == null) return;
    setState(() {
      if (editIndex == null) { target.add(result); } else { target[editIndex] = result; }
    });
    await _save();
  }
  Future<void> _delete(List<Map<String,dynamic>> list, int i) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('¿Eliminar elemento?'), content: const Text('Esta acción no se puede deshacer.'),
      actions: [TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Eliminar'))]));
    if (ok != true) return;
    setState(() => list.removeAt(i)); await _save();
  }
  Future<void> _settings() async {
    final minCtrl = TextEditingController(text: criterionMin.toString());
    final maxCtrl = TextEditingController(text: criterionMax.toString());
    String selectedCriterion = criterion;
    final result = await showDialog<Map<String,dynamic>>(context: context, builder: (ctx) =>
      AlertDialog(
        title: const Text('Criterio de evaluación'),
        content: StatefulBuilder(builder: (ctx, refresh) => Column(mainAxisSize:MainAxisSize.min, children:[
          DropdownButtonFormField<String>(
            initialValue:selectedCriterion,
            decoration:const InputDecoration(labelText:'Cálculo de la media'),
            items:['Media aritmética','Media ponderada'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),
            onChanged:(v)=>refresh(()=>selectedCriterion=v ?? selectedCriterion),
          ),
          TextField(controller:minCtrl, keyboardType:const TextInputType.numberWithOptions(decimal:true), decoration:const InputDecoration(labelText:'Nota mínima (X)')),
          TextField(controller:maxCtrl, keyboardType:const TextInputType.numberWithOptions(decimal:true), decoration:const InputDecoration(labelText:'Nota máxima (Y)')),
          const SizedBox(height:6),
          const Text('Las notas se podrán introducir dentro de este intervalo numérico.'),
        ])),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),
          FilledButton(onPressed:(){
            final min=double.tryParse(minCtrl.text.replaceAll(',','.'));
            final max=double.tryParse(maxCtrl.text.replaceAll(',','.'));
            if(min==null || max==null || min>=max) return;
            Navigator.pop(ctx, {'min':min,'max':max,'criterion':selectedCriterion});
          },child:const Text('Guardar')),
        ],
      ));
    if(result!=null) {
      setState(() { criterionMin=result['min']; criterionMax=result['max']; criterion=result['criterion']; });
      await _save();
    }
  }
  String _export() => jsonEncode({'app':'EstudioGo','classes':classes,'teachers':teachers,'exams':exams,'grades':grades,'criterion':criterion,'criterionMin':criterionMin,'criterionMax':criterionMax});
  Future<void> _importSnapshot(String raw) async {
    final d=jsonDecode(raw) as Map<String,dynamic>;
    if(d['app']!='EstudioGo') throw const FormatException('Copia no válida');
    List<Map<String,dynamic>> merge(List<Map<String,dynamic>> current,List<dynamic> incoming) {
      final result=[...current];
      for(final item in incoming.cast<Map<String,dynamic>>()) {
        if(!result.any((old)=>jsonEncode(old)==jsonEncode(item))) result.add(item);
      }
      return result;
    }
    final mergedClasses=merge(classes,d['classes'] as List? ?? []);
    final mergedTeachers=merge(teachers,d['teachers'] as List? ?? []);
    final mergedExams=merge(exams,d['exams'] as List? ?? []);
    final mergedGrades=merge(grades,d['grades'] as List? ?? []);
    setState((){
      classes..clear()..addAll(mergedClasses);
      teachers..clear()..addAll(mergedTeachers);
      exams..clear()..addAll(mergedExams);
      grades..clear()..addAll(mergedGrades);
      criterion=d['criterion']??criterion;
      criterionMin=(d['criterionMin'] as num?)?.toDouble() ?? criterionMin;
      criterionMax=(d['criterionMax'] as num?)?.toDouble() ?? criterionMax;
    });
    await _save();
  }
  Future<void> _scan() async {
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>ScanPage(onRead:(raw) async {
      if(raw.startsWith('http://') || raw.startsWith('https://')) {
        final result=await joinWifiSync(raw,_export());
        await _importSnapshot(result);
      } else {
        await _importSnapshot(raw);
      }
    })));
  }
  Future<void> _startWifiSync() async {
    try {
      final address=await startWifiSync(_export, _importSnapshot);
      if(!mounted) return;
      await showDialog(context:context,builder:(_)=>AlertDialog(
        title:const Text('Sincronización por Wi-Fi'),
        content:SizedBox(width:260,child:Column(mainAxisSize:MainAxisSize.min,children:[
          const Text('Mantén esta pantalla abierta. En el otro dispositivo, escanea este QR. Ambos deben estar conectados a la misma red Wi-Fi.'),
          const SizedBox(height:12),QrImageView(data:address,size:210),
          const SizedBox(height:8),SelectableText(address,style:const TextStyle(fontSize:11)),
        ])),
        actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cerrar'))]));
    } catch(e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('No se pudo iniciar la sincronización: $e')));
    }
  }
  Future<void> _qr() => showDialog(context: context, builder: (_) => AlertDialog(
    title: const Text('Transferir datos con QR'),
    content: SizedBox(width: 260, child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Escanea este código desde otro dispositivo EstudioGo.'),
      QrImageView(data: _export(), size: 220),
      const Text('El QR contiene una copia de tus datos.', style: TextStyle(fontSize: 12)),
    ])),
    actions: [TextButton(onPressed:()=>Navigator.pop(context), child:const Text('Cerrar'))]));

  Widget _tile(String title, String subtitle, IconData icon, {VoidCallback? onTap, Widget? trailing}) =>
    Card(child: ListTile(leading: CircleAvatar(backgroundColor:blue.withOpacity(.1),child:Icon(icon,color:blue)),
      title:Text(title),subtitle:Text(subtitle),trailing:trailing,onTap:onTap));
  Widget _list(List<Map<String,dynamic>> data, String kind, IconData icon) {
    if (data.isEmpty) return const Center(child: Text('Aún no hay elementos. Pulsa + para añadir el primero.'));
    return ListView(padding:const EdgeInsets.all(16),children:List.generate(data.length,(i) {
      final x=data[i];
      String sub='Asignatura';
      if (kind=='teachers') sub=x['contact'] ?? 'Profesor';
      if (kind=='classes') {
        final slots = _classSchedules(x);
        sub = [...slots.map((slot)=>'${slot['day']} ${slot['time']}'), if ((x['teacher']?.toString().isNotEmpty ?? false)) x['teacher'].toString()].join(' · ');
      }
      if (kind=='grades') sub=x['subject']+' · '+(x['value'] as num).toStringAsFixed(2)+'/10';
      if (kind=='exams') sub=x['subject']+' · '+DateFormat('dd/MM/yyyy').format(DateTime.parse(x['date']));
      return _tile(x['name'],sub,icon,onTap:()=>_add(kind,i),trailing:Row(mainAxisSize:MainAxisSize.min,children:[IconButton(tooltip:'Editar',icon:const Icon(Icons.edit_outlined),onPressed:()=>_add(kind,i)),IconButton(tooltip:'Eliminar',icon:const Icon(Icons.delete_outline),onPressed:()=>_delete(data,i))]));
    }));
  }
  DateTime selectedDay = DateTime.now();
  DateTime calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  int _weekdayNumber(String? day) => const {
    'Lunes': DateTime.monday, 'Martes': DateTime.tuesday,
    'Miércoles': DateTime.wednesday, 'Jueves': DateTime.thursday,
    'Viernes': DateTime.friday, 'Sábado': DateTime.saturday,
    'Domingo': DateTime.sunday,
  }[day] ?? 0;
  List<Map<String,String>> _classSchedules(Map<String,dynamic> item) {
    final raw = item['schedule'];
    if (raw is List) return raw.whereType<Map>().map((slot)=>{'day':slot['day']?.toString()??'','time':slot['time']?.toString()??'08:00'}).toList();
    if ((item['day']?.toString().isNotEmpty ?? false)) return [{'day':item['day'].toString(),'time':item['time']?.toString()??'08:00'}];
    return [];
  }

  Widget _calendar() {
    final firstWeekday = DateTime(calendarMonth.year, calendarMonth.month, 1).weekday;
    final days = DateUtils.getDaysInMonth(calendarMonth.year, calendarMonth.month);
    final cells = <Widget>[];
    for (int i=1; i<firstWeekday; i++) { cells.add(const SizedBox.shrink()); }
    for (int day=1; day<=days; day++) {
      final date=DateTime(calendarMonth.year,calendarMonth.month,day);
      final hasExam=exams.any((e){final d=DateTime.parse(e['date']);return d.year==date.year&&d.month==date.month&&d.day==date.day;});
      final hasClass=classes.any((c)=>_classSchedules(c).any((slot)=>_weekdayNumber(slot['day'])==date.weekday));
      final selected=date.year==selectedDay.year&&date.month==selectedDay.month&&date.day==selectedDay.day;
      cells.add(InkWell(borderRadius:BorderRadius.circular(24),onTap:()=>setState(()=>selectedDay=date),child:Center(child:SizedBox(width:40,height:40,child:Container(
        decoration:BoxDecoration(color:selected?blue.withOpacity(.16):null,border:selected?Border.all(color:blue):null,shape:BoxShape.circle),
        child:Column(mainAxisAlignment:MainAxisAlignment.center,mainAxisSize:MainAxisSize.min,children:[
          Text('$day',style:TextStyle(fontSize:12,fontWeight:selected?FontWeight.bold:FontWeight.normal)),
          Row(mainAxisAlignment:MainAxisAlignment.center,mainAxisSize:MainAxisSize.min,children:[
            if(hasClass) Container(width:4,height:4,margin:const EdgeInsets.symmetric(horizontal:1),decoration:const BoxDecoration(color:Color(0xFF16A34A),shape:BoxShape.circle)),
            if(hasExam) Container(width:4,height:4,margin:const EdgeInsets.symmetric(horizontal:1),decoration:const BoxDecoration(color:blue,shape:BoxShape.circle)),
          ])
        ]))))));
    }
    final dayClasses=<Map<String,dynamic>>[];
    for(int i=0;i<classes.length;i++) {
      if(_classSchedules(classes[i]).any((slot)=>_weekdayNumber(slot['day'])==selectedDay.weekday)) dayClasses.add(classes[i]);
    }
    final dayExams=<Map<String,dynamic>>[];
    for(final e in exams) {
      final d=DateTime.parse(e['date']);
      if(d.year==selectedDay.year&&d.month==selectedDay.month&&d.day==selectedDay.day) dayExams.add(e);
    }
    return Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(8,2,8,0),child:Row(children:[
        IconButton(onPressed:()=>setState(()=>calendarMonth=DateTime(calendarMonth.year,calendarMonth.month-1)),icon:const Icon(Icons.chevron_left)),
        Expanded(child:Center(child:Text('${['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'][calendarMonth.month-1]} ${calendarMonth.year}',style:const TextStyle(fontSize:16,fontWeight:FontWeight.bold)))),
        IconButton(visualDensity:VisualDensity.compact,onPressed:()=>setState(()=>calendarMonth=DateTime(calendarMonth.year,calendarMonth.month+1)),icon:const Icon(Icons.chevron_right)),
        TextButton(onPressed:()=>setState((){selectedDay=DateTime.now();calendarMonth=DateTime(selectedDay.year,selectedDay.month);}),child:const Text('Hoy'))
      ])),
      Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Row(children:['L','M','X','J','V','S','D'].map((d)=>Expanded(child:Center(child:Text(d,style:const TextStyle(fontSize:11,fontWeight:FontWeight.bold,color:Colors.grey))))).toList())),
      LayoutBuilder(builder:(context,constraints)=>Padding(padding:const EdgeInsets.symmetric(horizontal:8,vertical:2),child:GridView.count(
        shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:7,
        mainAxisSpacing:2,crossAxisSpacing:2,
        childAspectRatio:(constraints.maxWidth/7/44).clamp(1.0,5.0),
        children:cells))),
      const Padding(padding:EdgeInsets.symmetric(horizontal:16),child:Row(children:[
        Icon(Icons.circle,size:8,color:Color(0xFF16A34A)),SizedBox(width:5),Text('Clases',style:TextStyle(fontSize:12)),
        SizedBox(width:14),Icon(Icons.circle,size:8,color:blue),SizedBox(width:5),Text('Exámenes',style:TextStyle(fontSize:12))
      ])),
      const Divider(),
      Padding(padding:const EdgeInsets.symmetric(horizontal:16,vertical:8),child:Align(alignment:Alignment.centerLeft,child:Text('Agenda · ${DateFormat('dd/MM/yyyy').format(selectedDay)}',style:const TextStyle(fontWeight:FontWeight.bold)))),
      Expanded(child:ListView(children:[
        if(dayClasses.isEmpty && dayExams.isEmpty) const Padding(padding:EdgeInsets.all(24),child:Center(child:Text('No hay clases ni exámenes para este día.'))),
        ...dayClasses.map((c){
          final i=classes.indexOf(c);
          final slot=_classSchedules(c).firstWhere((slot)=>_weekdayNumber(slot['day'])==selectedDay.weekday,orElse:()=>{'time':''});
          final detail=[slot['time'],c['teacher']].where((v)=>v!=null&&v.toString().isNotEmpty).join(' · ');
          return _tile(c['name'],'Clase · $detail',Icons.menu_book,onTap:()=>_add('classes',i),trailing:Row(mainAxisSize:MainAxisSize.min,children:[IconButton(tooltip:'Editar clase',icon:const Icon(Icons.edit_outlined),onPressed:()=>_add('classes',i)),IconButton(tooltip:'Eliminar clase',icon:const Icon(Icons.delete_outline),onPressed:()=>_delete(classes,i))]));
        }),
        ...dayExams.map((e){
          final i=exams.indexOf(e);
          return _tile(e['name'],'Examen · ${e['subject']}',Icons.event,onTap:()=>_add('exams',i),trailing:Row(mainAxisSize:MainAxisSize.min,children:[IconButton(tooltip:'Editar examen',icon:const Icon(Icons.edit_outlined),onPressed:()=>_add('exams',i)),IconButton(tooltip:'Eliminar examen',icon:const Icon(Icons.delete_outline),onPressed:()=>_delete(exams,i))]));
        }),
      ]))
    ]);
  }

  Widget _statistics() {
    final subjects=classes.map((c)=>c['name'].toString()).toList();
    if(subjects.isEmpty) return const Center(child:Text('Añade asignaturas para ver sus estadísticas.'));
    return ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Estadísticas por asignatura',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
      const SizedBox(height:12),
      ...subjects.map((subject){final a=_average(subject); final count=grades.where((g)=>g['subject']==subject).length; final v=(a??0).clamp(0,10).toDouble(); return Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Expanded(child:Text(subject,style:const TextStyle(fontWeight:FontWeight.bold))),Text(a==null?'Sin notas':'${a.toStringAsFixed(2)}/10')]),const SizedBox(height:8),LinearProgressIndicator(value:v/10,minHeight:8),const SizedBox(height:6),Text('$count ${count==1?'nota':'notas'} registradas')])));}),
      const SizedBox(height:12),_tile('Media global',_average()==null?'Sin notas':'${_average()!.toStringAsFixed(2)} / 10',Icons.auto_graph),
    ]);
  }

  Widget _homeCalendar() {
    final firstWeekday = DateTime(calendarMonth.year, calendarMonth.month, 1).weekday;
    final days = DateUtils.getDaysInMonth(calendarMonth.year, calendarMonth.month);
    final cells = <Widget>[];
    for (int i=1; i<firstWeekday; i++) cells.add(const SizedBox.shrink());
    for (int day=1; day<=days; day++) {
      final date=DateTime(calendarMonth.year,calendarMonth.month,day);
      final hasExam=exams.any((e){final d=DateTime.parse(e['date']);return d.year==date.year&&d.month==date.month&&d.day==date.day;});
      final hasClass=classes.any((c)=>_weekdayNumber(c['day']?.toString())==date.weekday);
      final selected=date.year==selectedDay.year&&date.month==selectedDay.month&&date.day==selectedDay.day;
      cells.add(InkWell(borderRadius:BorderRadius.circular(24),onTap:()=>setState((){selectedDay=date;tab=3;}),child:Container(
        margin:const EdgeInsets.all(2),decoration:BoxDecoration(color:selected?blue.withOpacity(.16):null,border:selected?Border.all(color:blue):null,shape:BoxShape.circle),
        child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
          Text('$day',style:TextStyle(fontSize:10,fontWeight:selected?FontWeight.bold:FontWeight.normal)),
          Row(mainAxisAlignment:MainAxisAlignment.center,children:[
            if(hasClass) Container(width:4,height:4,margin:const EdgeInsets.symmetric(horizontal:1),decoration:const BoxDecoration(color:Color(0xFF16A34A),shape:BoxShape.circle)),
            if(hasExam) Container(width:4,height:4,margin:const EdgeInsets.symmetric(horizontal:1),decoration:const BoxDecoration(color:blue,shape:BoxShape.circle)),
          ])
        ]))));
    }
    return Card(child:Padding(padding:const EdgeInsets.all(8),child:Column(children:[
      Row(children:[
        const Expanded(child:Text('Calendario',style:TextStyle(fontSize:15,fontWeight:FontWeight.bold))),
        IconButton(visualDensity:VisualDensity.compact,onPressed:()=>setState(()=>calendarMonth=DateTime(calendarMonth.year,calendarMonth.month-1)),icon:const Icon(Icons.chevron_left)),
        Text('${['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'][calendarMonth.month-1]} ${calendarMonth.year}',style:const TextStyle(fontWeight:FontWeight.w600)),
        IconButton(visualDensity:VisualDensity.compact,onPressed:()=>setState(()=>calendarMonth=DateTime(calendarMonth.year,calendarMonth.month+1)),icon:const Icon(Icons.chevron_right)),
        TextButton(onPressed:()=>setState(()=>tab=3),child:const Text('Abrir')),
      ]),
      Row(children:['L','M','X','J','V','S','D'].map((d)=>Expanded(child:Center(child:Text(d,style:const TextStyle(fontSize:11,color:Colors.grey,fontWeight:FontWeight.bold))))).toList()),
      GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:7,childAspectRatio:1.65,children:cells),
      const Row(children:[Icon(Icons.circle,size:7,color:Color(0xFF16A34A)),SizedBox(width:4),Text('Clases',style:TextStyle(fontSize:11)),SizedBox(width:12),Icon(Icons.circle,size:7,color:blue),SizedBox(width:4),Text('Exámenes',style:TextStyle(fontSize:11))]),
    ])));
  }

  Widget _dashboard() {
    final avg=_average();
    final upcoming=exams.toList()..sort((a,b)=>DateTime.parse(a['date']).compareTo(DateTime.parse(b['date'])));
    void go(int destination) => setState(()=>tab=destination);
    void openExam(Map<String,dynamic> e) {
      final d=DateTime.parse(e['date']);
      setState((){selectedDay=d;calendarMonth=DateTime(d.year,d.month);tab=3;});
    }
    return ListView(padding:const EdgeInsets.all(16),children:[
      Container(padding:const EdgeInsets.all(24),decoration:BoxDecoration(
        gradient:const LinearGradient(colors:[Color(0xFF1D4ED8),Color(0xFF60A5FA)]),borderRadius:BorderRadius.circular(22)),
        child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('TU ESPACIO DE ESTUDIO',style:TextStyle(color:Colors.white70)),
          SizedBox(height:8),Text('Planifica. Organiza. Aprueba.',style:TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.bold)),
        ])),
      const SizedBox(height:12),
      _homeCalendar(),
      const SizedBox(height:12),
      _tile('Media general',avg==null?'Sin notas':avg.toStringAsFixed(2)+' / 10',Icons.auto_graph,onTap:()=>go(4)),
      GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:2,childAspectRatio:1.8,children:[
        _tile('Clases',classes.length.toString()+' asignaturas · Ver, editar y eliminar',Icons.menu_book,onTap:()=>go(5)),
        _tile('Profesores',teachers.length.toString(),Icons.person,onTap:()=>go(1)),
        _tile('Exámenes',exams.length.toString(),Icons.event,onTap:()=>go(3)),
        _tile('Notas',_average()==null?'Sin notas':'Media: ${_average()!.toStringAsFixed(2)} / 10',Icons.grade,onTap:()=>go(2)),
      ]),
      const Text('Próximos exámenes',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
      if(upcoming.isEmpty) const Text('Todavía no has añadido exámenes.')
      else ...upcoming.take(4).map((e)=>_tile(e['name'],e['subject']+' · '+DateFormat('dd/MM/yyyy').format(DateTime.parse(e['date'])),Icons.event,onTap:()=>openExam(e))),
      _tile('Criterio de evaluación','$criterion · ${criterionMin.toString()}–${criterionMax.toString()}',Icons.tune,onTap:_settings),
    ]);
  }
  @override Widget build(BuildContext context) {
    final wide=MediaQuery.sizeOf(context).width>=760;
    final views=[_dashboard(),_list(teachers,'teachers',Icons.person),_list(grades,'grades',Icons.grade),_calendar(),_statistics(),_list(classes,'classes',Icons.menu_book)];
    const nav=[
      NavigationDestination(icon:Icon(Icons.home_outlined),label:'Inicio'),
      NavigationDestination(icon:Icon(Icons.person),label:'Profesores'),
      NavigationDestination(icon:Icon(Icons.grade),label:'Notas'),
      NavigationDestination(icon:Icon(Icons.calendar_month),label:'Calendario'),
      NavigationDestination(icon:Icon(Icons.query_stats),label:'Estadísticas'),
      NavigationDestination(icon:Icon(Icons.menu_book),label:'Clases'),
    ];
    Future<void> addCalendarEntry() async {
      final kind=await showModalBottomSheet<String>(context:context,builder:(ctx)=>SafeArea(child:Wrap(children:[
        ListTile(leading:const Icon(Icons.menu_book),title:const Text('Añadir clase'),onTap:()=>Navigator.pop(ctx,'classes')),
        ListTile(leading:const Icon(Icons.event),title:const Text('Añadir examen'),onTap:()=>Navigator.pop(ctx,'exams')),
      ])));
      if(kind!=null) await _add(kind);
    }
    return Scaffold(
      appBar:AppBar(title:const Row(children:[
        EstudioGoMark(size:30),SizedBox(width:9),
        Text('Estudio',style:TextStyle(fontWeight:FontWeight.bold)),Text('Go',style:TextStyle(color:blue,fontWeight:FontWeight.bold))
      ]),
        actions:[IconButton(tooltip:'Tema oscuro',onPressed:()=>widget.onThemeChanged(!widget.dark),icon:Icon(widget.dark?Icons.light_mode:Icons.dark_mode)),IconButton(tooltip:'Sincronizar por Wi-Fi',onPressed:_startWifiSync,icon:const Icon(Icons.wifi)),IconButton(onPressed:_scan,icon:const Icon(Icons.qr_code_scanner)),IconButton(onPressed:_qr,icon:const Icon(Icons.qr_code_2))]),
      body:wide?Row(children:[
        NavigationRail(selectedIndex:tab,labelType:NavigationRailLabelType.all,onDestinationSelected:(v)=>setState(()=>tab=v),
          destinations:const [
            NavigationRailDestination(icon:Icon(Icons.home_outlined),label:Text('Inicio')),
            NavigationRailDestination(icon:Icon(Icons.person),label:Text('Profesores')),
            NavigationRailDestination(icon:Icon(Icons.grade),label:Text('Notas')),
            NavigationRailDestination(icon:Icon(Icons.calendar_month),label:Text('Calendario')),
            NavigationRailDestination(icon:Icon(Icons.query_stats),label:Text('Estadísticas')),
            NavigationRailDestination(icon:Icon(Icons.menu_book),label:Text('Clases'))]),
        const VerticalDivider(width:1),Expanded(child:views[tab])]):views[tab],
      floatingActionButton:(tab==0||tab==4)?null:FloatingActionButton(backgroundColor:blue,foregroundColor:Colors.white,
        onPressed:tab==3?addCalendarEntry:()=>_add(tab==1?'teachers':tab==5?'classes':'grades'),child:const Icon(Icons.add)),
      bottomNavigationBar:wide?null:NavigationBar(selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),destinations:nav),
    );
  }
}

class EstudioGoMark extends StatelessWidget {
  final double size;
  const EstudioGoMark({super.key,this.size=36});
  @override Widget build(BuildContext context)=>SizedBox(width:size,height:size,child:DecoratedBox(
    decoration:BoxDecoration(gradient:const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF1D4ED8),Color(0xFF60A5FA)]),borderRadius:BorderRadius.circular(size*.28)),
    child:Icon(Icons.menu_book_rounded,color:Colors.white,size:size*.62)));
}

class ScanPage extends StatefulWidget {
  final Future<void> Function(String) onRead;
  const ScanPage({super.key,required this.onRead});
  @override State<ScanPage> createState()=>_ScanPageState();
}
class _ScanPageState extends State<ScanPage> {
  bool done=false;
  final manualCode=TextEditingController();

  @override
  void dispose() {
    manualCode.dispose();
    super.dispose();
  }

  Future<void> _submit(String raw) async {
    if(done || raw.trim().isEmpty) return;
    setState(()=>done=true);
    try {
      await widget.onRead(raw.trim());
      if(mounted) Navigator.pop(context);
    } catch(e) {
      if(mounted) {
        setState(()=>done=false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content:Text('No se pudo sincronizar: $e')),
        );
      }
    }
  }

  @override Widget build(BuildContext context) {
    final isWindows=defaultTargetPlatform==TargetPlatform.windows;
    return Scaffold(
      appBar:AppBar(title:const Text('Escanear QR')),
      body:isWindows
        ? ListView(padding:const EdgeInsets.all(24),children:[
            const Icon(Icons.qr_code_scanner,size:64,color:blue),
            const SizedBox(height:16),
            const Text('En Windows no hay lector de cámara integrado. Para sincronizar, abre el QR en el PC y pega aquí la dirección que aparece debajo del código (empieza por http://).',
              textAlign:TextAlign.center),
            const SizedBox(height:18),
            TextField(controller:manualCode,keyboardType:TextInputType.url,
              decoration:const InputDecoration(labelText:'Dirección de sincronización',hintText:'http://192.168...:8787/sync?token=...',border:OutlineInputBorder())),
            const SizedBox(height:12),
            FilledButton.icon(onPressed:done?null:()=>_submit(manualCode.text),
              icon:const Icon(Icons.sync),label:const Text('Conectar y sincronizar')),
          ])
        : Column(children:[
            const Padding(padding:EdgeInsets.all(18),child:Text('Apunta la cámara al QR del otro dispositivo EstudioGo.')),
            Expanded(child:MobileScanner(onDetect:(capture) async {
              if(done || capture.barcodes.isEmpty) return;
              final raw=capture.barcodes.first.rawValue;
              if(raw==null) return;
              await _submit(raw);
            })),
          ]),
    );
  }
}
