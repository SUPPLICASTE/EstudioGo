import 'dart:convert';
import 'package:flutter/material.dart';
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
void main() => runApp(const EstudioGo());

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
  bool loading = true;
  String criterion = 'Media aritmética';
  final classes = <Map<String,dynamic>>[];
  final teachers = <Map<String,dynamic>>[];
  final exams = <Map<String,dynamic>>[];
  final grades = <Map<String,dynamic>>[];

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    void read(String key, List<Map<String,dynamic>> target) {
      final raw = p.getString(key);
      if (raw != null) target.addAll((jsonDecode(raw) as List).cast<Map<String,dynamic>>());
    }
    read('classes', classes); read('teachers', teachers); read('exams', exams); read('grades', grades);
    criterion = p.getString('criterion') ?? criterion;
    try { await initNotifications(); await _scheduleExamReminders(); } catch (_) {}
    if (mounted) setState(() => loading = false);
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
    final isTeacher = kind == 'teachers', isExam = kind == 'exams', isGrade = kind == 'grades';
    final result = await showDialog<Map<String,dynamic>>(context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
        title: Text(editIndex == null ? {'classes':'Nueva clase','teachers':'Nuevo profesor','exams':'Nuevo examen','grades':'Nueva nota'}[kind]! : 'Editar elemento'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: InputDecoration(labelText: isGrade ? 'Descripción' : isExam ? 'Nombre del examen' : isTeacher ? 'Nombre del profesor' : 'Asignatura')),
          if (isTeacher) TextField(controller: extra, decoration: const InputDecoration(labelText: 'Correo o contacto')),
          if (isExam || isGrade) DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Asignatura'),
            items: classes.map((c) => DropdownMenuItem(value: c['name'] as String, child: Text(c['name'] as String))).toList(),
            onChanged: (v) => refresh(() => subject = v)),
          if (isGrade) ...[
            TextField(controller: val, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Nota (0–10)')),
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
            if (isExam) item.addAll({'subject':subject,'date':date.toIso8601String()});
            if (isGrade) {
              final n = double.tryParse(val.text.replaceAll(',', '.'));
              if (n == null || n < 0 || n > 10) return;
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
    final v = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Criterio de evaluación'),
      content: Column(mainAxisSize: MainAxisSize.min, children: ['Media aritmética','Media ponderada'].map((s) =>
        RadioListTile<String>(value:s, groupValue:criterion, title:Text(s), onChanged:(x)=>Navigator.pop(ctx,x))).toList()),
      actions: [TextButton(onPressed:()=>Navigator.pop(ctx), child:const Text('Cerrar'))]));
    if (v != null) { setState(() => criterion = v); await _save(); }
  }
  String _export() => jsonEncode({'app':'EstudioGo','classes':classes,'teachers':teachers,'exams':exams,'grades':grades,'criterion':criterion});
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
    setState((){
      classes..clear()..addAll(merge([],d['classes'] as List? ?? []));
      teachers..clear()..addAll(merge([],d['teachers'] as List? ?? []));
      exams..clear()..addAll(merge([],d['exams'] as List? ?? []));
      grades..clear()..addAll(merge([],d['grades'] as List? ?? []));
      criterion=d['criterion']??criterion;
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
      if (kind=='grades') sub=x['subject']+' · '+(x['value'] as num).toStringAsFixed(2)+'/10';
      if (kind=='exams') sub=x['subject']+' · '+DateFormat('dd/MM/yyyy').format(DateTime.parse(x['date']));
      return _tile(x['name'],sub,icon,onTap:()=>_add(kind,i),trailing:Row(mainAxisSize:MainAxisSize.min,children:[IconButton(tooltip:'Editar',icon:const Icon(Icons.edit_outlined),onPressed:()=>_add(kind,i)),IconButton(tooltip:'Eliminar',icon:const Icon(Icons.delete_outline),onPressed:()=>_delete(data,i))]));
    }));
  }
  DateTime selectedDay = DateTime.now();
  DateTime calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  Widget _calendar() {
    final firstWeekday = DateTime(calendarMonth.year, calendarMonth.month, 1).weekday;
    final days = DateUtils.getDaysInMonth(calendarMonth.year, calendarMonth.month);
    final cells = <Widget>[];
    for (int i=1; i<firstWeekday; i++) { cells.add(const SizedBox.shrink()); }
    for (int day=1; day<=days; day++) {
      final date=DateTime(calendarMonth.year,calendarMonth.month,day);
      final hasExam=exams.any((e){final d=DateTime.parse(e['date']);return d.year==date.year&&d.month==date.month&&d.day==date.day;});
      final selected=date.year==selectedDay.year&&date.month==selectedDay.month&&date.day==selectedDay.day;
      cells.add(InkWell(borderRadius:BorderRadius.circular(30),onTap:()=>setState(()=>selectedDay=date),child:Container(
        margin:const EdgeInsets.all(3),decoration:BoxDecoration(color:selected?blue.withOpacity(.16):null,border:selected?Border.all(color:blue):null,shape:BoxShape.circle),
        child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text('$day',style:TextStyle(fontWeight:selected?FontWeight.bold:FontWeight.normal)),if(hasExam) Container(width:5,height:5,decoration:const BoxDecoration(color:blue,shape:BoxShape.circle))]))));
    }
    final dayExams=exams.where((e){final d=DateTime.parse(e['date']);return d.year==selectedDay.year&&d.month==selectedDay.month&&d.day==selectedDay.day;}).toList();
    return Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(16,8,16,0),child:Row(children:[
        IconButton(onPressed:()=>setState(()=>calendarMonth=DateTime(calendarMonth.year,calendarMonth.month-1)),icon:const Icon(Icons.chevron_left)),
        Expanded(child:Center(child:Text(DateFormat('MMMM yyyy','es').format(calendarMonth),style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)))),
        IconButton(onPressed:()=>setState(()=>calendarMonth=DateTime(calendarMonth.year,calendarMonth.month+1)),icon:const Icon(Icons.chevron_right)),
        TextButton(onPressed:()=>setState((){selectedDay=DateTime.now();calendarMonth=DateTime(selectedDay.year,selectedDay.month);}),child:const Text('Hoy'))
      ])),
      const Padding(padding:EdgeInsets.symmetric(horizontal:12),child:Row(children:['L','M','X','J','V','S','D'].map((d)=>Expanded(child:Center(child:Text(d,style:TextStyle(fontWeight:FontWeight.bold,color:Colors.grey))))).toList())),
      Padding(padding:const EdgeInsets.all(8),child:GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:7,childAspectRatio:1.15,children:cells)),
      const Divider(),
      Padding(padding:const EdgeInsets.symmetric(horizontal:16,vertical:8),child:Align(alignment:Alignment.centerLeft,child:Text('Exámenes · ${DateFormat('dd/MM/yyyy').format(selectedDay)}',style:const TextStyle(fontWeight:FontWeight.bold)))),
      Expanded(child:dayExams.isEmpty?const Center(child:Text('No hay exámenes para este día.')):ListView(children:dayExams.map((e)=>_tile(e['name'],e['subject'],Icons.event)).toList()))
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

  Widget _dashboard() {
    final avg=_average();
    final upcoming=exams.toList()..sort((a,b)=>DateTime.parse(a['date']).compareTo(DateTime.parse(b['date'])));
    return ListView(padding:const EdgeInsets.all(16),children:[
      Container(padding:const EdgeInsets.all(24),decoration:BoxDecoration(
        gradient:const LinearGradient(colors:[Color(0xFF1D4ED8),Color(0xFF60A5FA)]),borderRadius:BorderRadius.circular(22)),
        child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('TU ESPACIO DE ESTUDIO',style:TextStyle(color:Colors.white70)),
          SizedBox(height:8),Text('Planifica. Organiza. Aprueba.',style:TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.bold)),
        ])),
      const SizedBox(height:12),
      _tile('Media general',avg==null?'Sin notas':avg.toStringAsFixed(2)+' / 10',Icons.auto_graph),
      GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:2,childAspectRatio:1.8,children:[
        _tile('Clases',classes.length.toString(),Icons.menu_book),
        _tile('Profesores',teachers.length.toString(),Icons.person),
        _tile('Exámenes',exams.length.toString(),Icons.event),
        _tile('Notas',grades.length.toString(),Icons.grade),
      ]),
      const Text('Próximos exámenes',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
      if(upcoming.isEmpty) const Text('Todavía no has añadido exámenes.')
      else ...upcoming.take(4).map((e)=>_tile(e['name'],e['subject']+' · '+DateFormat('dd/MM/yyyy').format(DateTime.parse(e['date'])),Icons.event)),
      _tile('Criterio de evaluación',criterion,Icons.tune,onTap:_settings),
    ]);
  }
  @override Widget build(BuildContext context) {
    if (loading) return const Scaffold(body:Center(child:CircularProgressIndicator()));
    final wide=MediaQuery.sizeOf(context).width>=760;
    final views=[_dashboard(),_list(classes,'classes',Icons.menu_book),_list(teachers,'teachers',Icons.person),_list(exams,'exams',Icons.event),_list(grades,'grades',Icons.grade),_calendar(),_statistics()];
    const nav=[
      NavigationDestination(icon:Icon(Icons.home_outlined),label:'Inicio'),
      NavigationDestination(icon:Icon(Icons.menu_book),label:'Clases'),
      NavigationDestination(icon:Icon(Icons.person),label:'Profesores'),
      NavigationDestination(icon:Icon(Icons.event),label:'Exámenes'),
      NavigationDestination(icon:Icon(Icons.grade),label:'Notas'),
      NavigationDestination(icon:Icon(Icons.calendar_month),label:'Calendario'),
      NavigationDestination(icon:Icon(Icons.query_stats),label:'Estadísticas'),
    ];
    return Scaffold(
      appBar:AppBar(title:const Row(children:[Icon(Icons.school,color:blue),SizedBox(width:8),Text('Estudio',style:TextStyle(fontWeight:FontWeight.bold)),Text('Go',style:TextStyle(color:blue,fontWeight:FontWeight.bold))]),
        actions:[IconButton(tooltip:'Tema oscuro',onPressed:()=>widget.onThemeChanged(!widget.dark),icon:Icon(widget.dark?Icons.light_mode:Icons.dark_mode)),IconButton(tooltip:'Sincronizar por Wi-Fi',onPressed:_startWifiSync,icon:const Icon(Icons.wifi)),IconButton(onPressed:_scan,icon:const Icon(Icons.qr_code_scanner)),IconButton(onPressed:_qr,icon:const Icon(Icons.qr_code_2)),IconButton(onPressed:_settings,icon:const Icon(Icons.tune))]),
      body:wide?Row(children:[
        NavigationRail(selectedIndex:tab,labelType:NavigationRailLabelType.all,onDestinationSelected:(v)=>setState(()=>tab=v),
          destinations:const [
            NavigationRailDestination(icon:Icon(Icons.home_outlined),label:Text('Inicio')),
            NavigationRailDestination(icon:Icon(Icons.menu_book),label:Text('Clases')),
            NavigationRailDestination(icon:Icon(Icons.person),label:Text('Profesores')),
            NavigationRailDestination(icon:Icon(Icons.event),label:Text('Exámenes')),
            NavigationRailDestination(icon:Icon(Icons.grade),label:Text('Notas')),
            NavigationRailDestination(icon:Icon(Icons.calendar_month),label:Text('Calendario')),
            NavigationRailDestination(icon:Icon(Icons.query_stats),label:Text('Estadísticas'))]),
        const VerticalDivider(width:1),Expanded(child:views[tab])]):views[tab],
      floatingActionButton:tab==0?null:FloatingActionButton(backgroundColor:blue,foregroundColor:Colors.white,
        onPressed:()=>_add(['','classes','teachers','exams','grades','exams','classes'][tab]),child:const Icon(Icons.add)),
      bottomNavigationBar:wide?null:NavigationBar(selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),destinations:nav),
    );
  }
}

class ScanPage extends StatefulWidget {
  final Future<void> Function(String) onRead;
  const ScanPage({super.key,required this.onRead});
  @override State<ScanPage> createState()=>_ScanPageState();
}
class _ScanPageState extends State<ScanPage> {
  bool done=false;
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Escanear QR')),
    body:Column(children:[
      const Padding(padding:EdgeInsets.all(18),child:Text('Apunta la cámara al QR del otro dispositivo EstudioGo.')),
      Expanded(child:MobileScanner(onDetect:(capture) async {
        if(done || capture.barcodes.isEmpty) return;
        final raw=capture.barcodes.first.rawValue;
        if(raw==null) return;
        done=true;
        try { await widget.onRead(raw); if(mounted) Navigator.pop(context); }
        catch (_) { done=false; if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Código QR no válido.'))); }
      })),
    ]));
}
