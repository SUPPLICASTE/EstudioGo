import 'dart:convert';
import 'dart:io';
import 'dart:math';

HttpServer? _server;
String? _token;
Future<String> startWifiSync(String Function() snapshot, Future<void> Function(String) receive) async {
  await _server?.close(force:true);
  final random=Random.secure();
  _token=List.generate(24,(_)=>random.nextInt(16).toRadixString(16)).join();
  _server=await HttpServer.bind(InternetAddress.anyIPv4,8787,shared:true);
  _server!.listen((request) async {
    try {
      if(request.uri.path!='/sync' || request.uri.queryParameters['token']!=_token) {
        request.response.statusCode=HttpStatus.forbidden; await request.response.close(); return;
      }
      if(request.method=='GET') {
        request.response.headers.contentType=ContentType.json;
        request.response.write(snapshot()); await request.response.close(); return;
      }
      if(request.method=='POST') {
        final body=await utf8.decoder.bind(request).join();
        await receive(body);
        request.response.headers.contentType=ContentType.json;
        request.response.write(snapshot()); await request.response.close(); return;
      }
      request.response.statusCode=HttpStatus.methodNotAllowed; await request.response.close();
    } catch (_) { request.response.statusCode=HttpStatus.internalServerError; await request.response.close(); }
  });
  final interfaces=await NetworkInterface.list(type:InternetAddressType.IPv4,includeLoopback:false);
  final addresses=interfaces.expand((i)=>i.addresses).where((a)=>!a.isLoopback).toList();
  if(addresses.isEmpty) { await _server!.close(force:true); _server=null; throw StateError('No se encontró una dirección IPv4 local.'); }
  return 'http://${addresses.first.address}:8787/sync?token=$_token';
}
Future<String> joinWifiSync(String address, String snapshot) async {
  final uri=Uri.parse(address);
  if(uri.scheme!='http' || uri.path!='/sync' || uri.queryParameters['token']==null) throw const FormatException('Código de sincronización no válido');
  final client=HttpClient()..connectionTimeout=const Duration(seconds:8);
  try {
    final request=await client.postUrl(uri);
    request.headers.contentType=ContentType.json;
    request.write(snapshot);
    final response=await request.close().timeout(const Duration(seconds:12));
    final body=await utf8.decoder.bind(response).join();
    if(response.statusCode!=HttpStatus.ok) throw HttpException('El dispositivo anfitrión rechazó la conexión.');
    return body;
  } finally { client.close(force:true); }
}
