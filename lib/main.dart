import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';

const blue = Color(0xFF2563EB);
void main() => runApp(const EstudioGo());

class EstudioGo extends StatelessWidget {
  const EstudioGo({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'EstudioGo', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: blue),
      scaffoldBackgroundColor: const Color(0xFFF6F8FC)),
    home: const Planner());
}

class Planner extends StatefulWidget {
  const Planner({super.key});
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
    if (mounted) setState(() => loading = false);
  }
  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('classes', jsonEncode(classes));
    await p.setString('teachers', jsonEncode(teachers));
    await p.setString('exams', jsonEncode(exams));
    await p.setString('grades', jsonEncode(grades));
    await p.setString('criterion', criterion);
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
    final name = TextEditingController(text: old?['name']?.toString() ?? ''), extra = TextEditingController(text: kind == 'teachers' ? old?['contact']?.toString() ?? '' : kind == 'grades' ? old?['weight']?.toString() ?? '' : ''), val = TextEditingController(text: old?['value']?.toString() ?? '');
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
  Future<void> _delete(List<Map<String,dynamic>> list, int i) async { setState(() => list.removeAt(i)); await _save(); }
  Future<void> _settings() async {
    final v = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Criterio de evaluación'),
      content: Column(mainAxisSize: MainAxisSize.min, children: ['Media aritmética','Media ponderada'].map((s) =>
        RadioListTile<String>(value:s, groupValue:criterion, title:Text(s), onChanged:(x)=>Navigator.pop(ctx,x))).toList()),
      actions: [TextButton(onPressed:()=>Navigator.pop(ctx), child:const Text('Cerrar'))]));
    if (v != null) { setState(() => criterion = v); await _save(); }
  }
  String _export() => jsonEncode({'app':'EstudioGo','classes':classes,'teachers':teachers,'exams':exams,'grades':grades,'criterion':criterion});
  Future<void> _scan() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ScanPage(onRead: (raw) async {
      final d = jsonDecode(raw) as Map<String,dynamic>;
      if (d['app'] != 'EstudioGo') throw const FormatException();
      setState(() {
        classes.addAll((d['classes'] as List? ?? []).cast<Map<String,dynamic>>());
        teachers.addAll((d['teachers'] as List? ?? []).cast<Map<String,dynamic>>());
        exams.addAll((d['exams'] as List? ?? []).cast<Map<String,dynamic>>());
        grades.addAll((d['grades'] as List? ?? []).cast<Map<String,dynamic>>());
        criterion = d['criterion'] ?? criterion;
      });
      await _save();
    })));
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
  Widget _calendar() => Column(children:[
    CalendarDatePicker(firstDate:DateTime(2020),lastDate:DateTime(2035),initialDate:selectedDay,onDateChanged:(d)=>setState(()=>selectedDay=d)),
    const Divider(),
    Expanded(child:Builder(builder:(context){
      final dayExams=exams.where((e){final d=DateTime.parse(e['date']);return d.year==selectedDay.year&&d.month==selectedDay.month&&d.day==selectedDay.day;}).toList();
      if(dayExams.isEmpty) return const Center(child:Text('No hay exámenes para este día.'));
      return ListView(children:dayExams.map((e)=>_tile(e['name'],e['subject']+' · '+DateFormat('dd/MM/yyyy').format(DateTime.parse(e['date'])),Icons.event)).toList());
    }))
  ]);

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
    final views=[_dashboard(),_list(classes,'classes',Icons.menu_book),_list(teachers,'teachers',Icons.person),_list(exams,'exams',Icons.event),_list(grades,'grades',Icons.grade),_calendar()];
    const nav=[
      NavigationDestination(icon:Icon(Icons.home_outlined),label:'Inicio'),
      NavigationDestination(icon:Icon(Icons.menu_book),label:'Clases'),
      NavigationDestination(icon:Icon(Icons.person),label:'Profesores'),
      NavigationDestination(icon:Icon(Icons.event),label:'Exámenes'),
      NavigationDestination(icon:Icon(Icons.grade),label:'Notas'),
      NavigationDestination(icon:Icon(Icons.calendar_month),label:'Calendario'),
    ];
    return Scaffold(
      appBar:AppBar(title:const Row(children:[Icon(Icons.school,color:blue),SizedBox(width:8),Text('Estudio',style:TextStyle(fontWeight:FontWeight.bold)),Text('Go',style:TextStyle(color:blue,fontWeight:FontWeight.bold))]),
        actions:[IconButton(onPressed:_scan,icon:const Icon(Icons.qr_code_scanner)),IconButton(onPressed:_qr,icon:const Icon(Icons.qr_code_2)),IconButton(onPressed:_settings,icon:const Icon(Icons.tune))]),
      body:wide?Row(children:[
        NavigationRail(selectedIndex:tab,labelType:NavigationRailLabelType.all,onDestinationSelected:(v)=>setState(()=>tab=v),
          destinations:const [
            NavigationRailDestination(icon:Icon(Icons.home_outlined),label:Text('Inicio')),
            NavigationRailDestination(icon:Icon(Icons.menu_book),label:Text('Clases')),
            NavigationRailDestination(icon:Icon(Icons.person),label:Text('Profesores')),
            NavigationRailDestination(icon:Icon(Icons.event),label:Text('Exámenes')),
            NavigationRailDestination(icon:Icon(Icons.grade),label:Text('Notas')),
            NavigationRailDestination(icon:Icon(Icons.calendar_month),label:Text('Calendario'))]),
        const VerticalDivider(width:1),Expanded(child:views[tab])]):views[tab],
      floatingActionButton:tab==0?null:FloatingActionButton(backgroundColor:blue,foregroundColor:Colors.white,
        onPressed:()=>_add(['','classes','teachers','exams','grades','exams'][tab]),child:const Icon(Icons.add)),
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
