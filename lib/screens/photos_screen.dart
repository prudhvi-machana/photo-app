import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import '../models/album.dart';
import '../models/local_media.dart';
import '../models/photo.dart';
import '../services/api_service.dart';
import '../widgets/photo_thumbnail.dart';
import 'local_media_viewer_screen.dart';
import 'photo_viewer_screen.dart';
import 'trash_screen.dart';
import 'upload_photos_screen.dart';

class PhotosScreen extends StatefulWidget {
  final String token;
  const PhotosScreen({super.key, required this.token});
  @override State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> {
  final ApiService _apiService = ApiService();
  List<Photo> _cloudPhotos = [];
  List<LocalMedia> _localMedia = [];
  Map<DateTime, List<_MediaItem>> _mediaGroups = {};
  bool _isLoading = true;
  bool _hasLocalPermission = false;
  String? _errorMessage;
  int _crossAxisCount = 3;
  final ScrollController _scrollController = ScrollController();

  final Map<int, Offset> _pointers = {};
  double? _pinchStartDistance;
  int _pinchStartColumns = 3;
  bool _isPinching = false;
  bool _pinchDirectionLocked = false;
  double _lastPinchRatio = 1.0;
  static const double _pinchThreshold = 0.10;
  final Set<String> _selectedKeys = {};
  bool _isSelectionMode = false;
  bool _isActionRunning = false;

  @override void initState(){super.initState();_apiService.setToken(widget.token);_loadMedia();}
  @override void dispose(){_scrollController.dispose();super.dispose();}

  Future<void> _loadMedia() async {
    try {
      final cloudFuture=_apiService.getPhotos();
      final permission=await PhotoManager.requestPermissionExtend();
      List<LocalMedia> local=[];
      if(permission.hasAccess){
        const pageSize=250;
        var start=0;
        while(true){
          final page=await PhotoManager.getAssetListRange(start:start,end:start+pageSize,type:RequestType.common);
          if(page.isEmpty)break;
          for(final asset in page){
            if(asset.isTrashed)continue;
            // AssetEntity already exposes its creation date and id; avoid an
            // expensive MediaStore title lookup for every item.
            local.add(LocalMedia(asset:asset,filename:asset.title ?? ''));
          }
          if(page.length<pageSize)break;
          start+=page.length;
        }
      }
      final cloud=await cloudFuture;
      final cloudNames=<String>{for(final photo in cloud)photo.originalFilename.trim().toLowerCase()};
      local=[for(final item in local)LocalMedia(asset:item.asset,filename:item.filename,alsoInCloud:item.filename.isNotEmpty&&cloudNames.contains(item.filename.trim().toLowerCase()))];
      final groups=_buildGroups(cloud,local);
      if(!mounted)return;
      setState((){_cloudPhotos=cloud;_localMedia=local;_mediaGroups=groups;_hasLocalPermission=permission.hasAccess;_isLoading=false;_errorMessage=null;});
    }catch(_){if(!mounted)return;setState((){_isLoading=false;_errorMessage='Failed to load photos.';});}
  }

  Map<DateTime,List<_MediaItem>> _buildGroups(List<Photo> cloud,List<LocalMedia> local){
    final items=<_MediaItem>[];
    final localNames={for(final item in local)if(item.filename.isNotEmpty)item.filename.trim().toLowerCase()};
    for(final photo in cloud)items.add(_MediaItem.cloud(photo,alsoLocal:localNames.contains(photo.originalFilename.trim().toLowerCase())));
    final cloudNames={for(final photo in cloud)photo.originalFilename.trim().toLowerCase()};
    for(final item in local)if(item.filename.isEmpty||!cloudNames.contains(item.filename.trim().toLowerCase()))items.add(_MediaItem.local(item));
    items.sort((a,b)=>b.date.compareTo(a.date));
    final groups=<DateTime,List<_MediaItem>>{};
    for(final item in items){final d=item.date;final key=DateTime(d.year,d.month,d.day);groups.putIfAbsent(key,()=>[]).add(item);}
    return groups;
  }

  Future<void> _refresh()async=>_loadMedia();
  void _pointerDown(PointerDownEvent event){_pointers[event.pointer]=event.position;if(_pointers.length==2){_pinchStartDistance=_distanceBetweenPointers();_pinchStartColumns=_crossAxisCount;_lastPinchRatio=1.0;_pinchDirectionLocked=false;setState(()=>_isPinching=true);}}
  void _pointerMove(PointerMoveEvent event){if(!_pointers.containsKey(event.pointer))return;_pointers[event.pointer]=event.position;if(!_isPinching||_pointers.length!=2||_pinchStartDistance==null)return;final distance=_distanceBetweenPointers();if(distance<=0)return;final ratio=_pinchStartDistance!/distance;if(!_pinchDirectionLocked){if((ratio-1).abs()<_pinchThreshold)return;_pinchDirectionLocked=true;}if((_lastPinchRatio-ratio).abs()<0.025)return;_lastPinchRatio=ratio;final next=(_pinchStartColumns*ratio).round().clamp(2,6);if(next!=_crossAxisCount)setState(()=>_crossAxisCount=next);}
  void _pointerUp(PointerEvent event){_pointers.remove(event.pointer);if(_pointers.length<2&&_isPinching){_pinchStartDistance=null;_pinchDirectionLocked=false;setState(()=>_isPinching=false);}}
  double _distanceBetweenPointers(){if(_pointers.length<2)return 0;final v=_pointers.values.toList();final dx=v[0].dx-v[1].dx,dy=v[0].dy-v[1].dy;return math.sqrt(dx*dx+dy*dy);}
  String _dateLabel(DateTime date){final now=DateTime.now(),today=DateTime(now.year,now.month,now.day),yesterday=today.subtract(const Duration(days:1));if(date==today)return'Today';if(date==yesterday)return'Yesterday';const m=['January','February','March','April','May','June','July','August','September','October','November','December'];return date.year==today.year?'${m[date.month-1]} ${date.day}':'${m[date.month-1]} ${date.day}, ${date.year}';}
  String _keyFor(_MediaItem item)=>item.isCloud?'cloud:${item.cloud!.id}':'local:${item.local!.asset.id}';
  bool _isSelected(_MediaItem item)=>_selectedKeys.contains(_keyFor(item));
  List<Photo> get _selectedCloudPhotos=>[for(final p in _cloudPhotos)if(_selectedKeys.contains('cloud:${p.id}'))p];
  void _enterSelection(_MediaItem item){if(_isPinching)return;setState((){_isSelectionMode=true;_selectedKeys.add(_keyFor(item));});}
  void _toggleSelection(_MediaItem item){final key=_keyFor(item);setState((){if(_selectedKeys.contains(key))_selectedKeys.remove(key);else _selectedKeys.add(key);if(_selectedKeys.isEmpty)_isSelectionMode=false;});}
  void _handleTap(_MediaItem item){if(_isSelectionMode){_toggleSelection(item);}else if(item.isCloud){_openCloudPhoto(item.cloud!);}else{_openLocalPhoto(item.local!);}}
  void _clearSelection(){setState((){_selectedKeys.clear();_isSelectionMode=false;});}
  void _selectAll(){final all=[for(final list in _mediaGroups.values)...list];final allSelected=all.isNotEmpty&&_selectedKeys.length==all.length;setState((){_isSelectionMode=true;_selectedKeys.clear();if(!allSelected)_selectedKeys.addAll(all.map(_keyFor));});}
  Future<void> _moveSelectedToTrash()async{final selected=_selectedCloudPhotos;if(selected.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Only cloud photos can be moved to Trash.')));return;}final c=selected.length,t=_selectedKeys.length;final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Move to Trash?'),content:Text('Move $c cloud ${c==1?'photo':'photos'} out of $t selected ${t==1?'file':'files'} to Trash? You can restore them for 30 days.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Move to Trash'))]));if(ok!=true)return;setState(()=>_isActionRunning=true);var success=0,failed=0;for(final p in selected){try{await _apiService.movePhotoToTrash(p.id);success++;}catch(_){failed++;}}if(!mounted)return;setState(()=>_isActionRunning=false);_clearSelection();await _refresh();if(!mounted)return;ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(failed==0?'$success photo${success==1?'':'s'} moved to Trash.':'$success moved, $failed failed.')));}
  Future<void> _addSelectedToAlbum()async{final selected=_selectedCloudPhotos;if(selected.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Only cloud photos can be added to albums.')));return;}setState(()=>_isActionRunning=true);List<Album> albums;try{albums=await _apiService.getAlbums();}catch(e){if(!mounted)return;setState(()=>_isActionRunning=false);ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Failed to load albums: $e')));return;}if(!mounted)return;setState(()=>_isActionRunning=false);if(albums.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('No albums available.')));return;}final album=await showDialog<Album>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Add to album'),content:SizedBox(width:double.maxFinite,height:math.min(360,albums.length*56.0),child:ListView.builder(itemCount:albums.length,itemBuilder:(_,i){final a=albums[i];return ListTile(leading:const Icon(Icons.photo_album_outlined),title:Text(a.name),onTap:()=>Navigator.pop(ctx,a));})),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel'))]));if(album==null||!mounted)return;setState(()=>_isActionRunning=true);var added=0,already=0,failed=0;for(final p in selected){try{await _apiService.addPhotoToAlbum(album.id,p.id);added++;}catch(e){if(e.toString().contains('409'))already++;else failed++;}}if(!mounted)return;setState(()=>_isActionRunning=false);_clearSelection();ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(failed==0&&already==0?'$added photo${added==1?'':'s'} added to "${album.name}".':'$added added, $already already there, $failed failed.')));}
  void _openCloudPhoto(Photo p)=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>PhotoViewerScreen(photos:_cloudPhotos,initialIndex:_cloudPhotos.indexOf(p),token:widget.token)));
  void _openLocalPhoto(LocalMedia m)=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>LocalMediaViewerScreen(asset:m.asset)));
  Future<void> _openTrash()async{await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>TrashScreen(token:widget.token)));if(mounted)await _refresh();}
  Future<void> _openUploadPhotos()async{final uploaded=await Navigator.of(context).push<bool>(MaterialPageRoute(builder:(_)=>UploadPhotosScreen(token:widget.token)));if(uploaded==true&&mounted)await _refresh();}

  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(leading:_isSelectionMode?IconButton(icon:const Icon(Icons.close),onPressed:_clearSelection):null,title:_isSelectionMode?Text('${_selectedKeys.length} selected'):const Text('Photos'),actions:_isSelectionMode?[if(_isActionRunning)const Padding(padding:EdgeInsets.symmetric(horizontal:16),child:Center(child:SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)))),if(!_isActionRunning)IconButton(tooltip:'Select all',icon:const Icon(Icons.select_all),onPressed:_selectAll),if(!_isActionRunning)IconButton(tooltip:'Add to album',icon:const Icon(Icons.add_to_photos_outlined),onPressed:_addSelectedToAlbum),if(!_isActionRunning)IconButton(tooltip:'Move cloud photos to Trash',icon:const Icon(Icons.delete_outline),onPressed:_moveSelectedToTrash)]:[IconButton(tooltip:'Refresh',icon:const Icon(Icons.refresh),onPressed:_refresh),IconButton(tooltip:'Trash',icon:const Icon(Icons.delete_outline),onPressed:_openTrash)],),floatingActionButton:_isSelectionMode?null:FloatingActionButton(onPressed:_openUploadPhotos,child:const Icon(Icons.add)),body:_buildBody());

  Widget _buildBody(){if(_isLoading)return const Center(child:CircularProgressIndicator());if(_errorMessage!=null)return Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text(_errorMessage!),const SizedBox(height:16),FilledButton(onPressed:_loadMedia,child:const Text('Retry'))]));if(!_hasLocalPermission&&_cloudPhotos.isEmpty)return const Center(child:Text('Allow photo access to see your device media.'));final groups=_mediaGroups,dates=groups.keys.toList()..sort((a,b)=>b.compareTo(a));return Listener(behavior:HitTestBehavior.translucent,onPointerDown:_pointerDown,onPointerMove:_pointerMove,onPointerUp:_pointerUp,onPointerCancel:_pointerUp,child:RefreshIndicator(onRefresh:_refresh,child:RawScrollbar(controller:_scrollController,thumbVisibility:true,interactive:true,minThumbLength:48,thickness:5,child:CustomScrollView(controller:_scrollController,physics:_isPinching?const NeverScrollableScrollPhysics():const AlwaysScrollableScrollPhysics(),slivers:[if(!_hasLocalPermission)const SliverToBoxAdapter(child:Padding(padding:EdgeInsets.fromLTRB(12,10,12,0),child:Text('Device photos are hidden until photo access is allowed.'))),for(final date in dates)...[SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.fromLTRB(12,14,12,8),child:Text(_dateLabel(date),style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w600)))),SliverPadding(padding:const EdgeInsets.symmetric(horizontal:2),sliver:SliverGrid(delegate:SliverChildBuilderDelegate((context,index)=>_buildMediaTile(groups[date]![index]),childCount:groups[date]!.length),gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:_crossAxisCount,crossAxisSpacing:2,mainAxisSpacing:2,childAspectRatio:1)))],const SliverToBoxAdapter(child:SizedBox(height:24))]))));}
  Widget _buildMediaTile(_MediaItem item){final selected=_isSelected(item);Widget image;if(item.isCloud){image=PhotoThumbnail(photo:item.cloud!,token:widget.token);}else{final l=item.local!;image=Stack(fit:StackFit.expand,children:[AssetEntityImage(l.asset,isOriginal:false,thumbnailSize:const ThumbnailSize.square(300),thumbnailFormat:ThumbnailFormat.jpeg,fit:BoxFit.cover),if(l.isVideo)const Positioned(right:8,bottom:8,child:Icon(Icons.play_circle_fill,color:Colors.white,size:28))]);}return GestureDetector(onTap:()=>_handleTap(item),onLongPress:()=>_enterSelection(item),child:Stack(fit:StackFit.expand,children:[image,if(item.isCloud)_buildStatusBadge(local:item.alsoLocal,cloud:true)else _buildStatusBadge(local:true,cloud:item.local!.alsoInCloud),if(selected)Container(color:Theme.of(context).colorScheme.primary.withValues(alpha:.38),child:Align(alignment:Alignment.topLeft,child:Container(margin:const EdgeInsets.all(6),decoration:BoxDecoration(color:Theme.of(context).colorScheme.primary,shape:BoxShape.circle),padding:const EdgeInsets.all(2),child:const Icon(Icons.check,color:Colors.white,size:18))))]));}
  Widget _buildStatusBadge({required bool local,required bool cloud}){final icon=local&&cloud?Icons.cloud_done:cloud?Icons.cloud_done:Icons.smartphone;final label=local&&cloud?'On device + cloud':cloud?'Cloud':'On device';return Positioned(top:5,right:5,child:Tooltip(message:label,child:Container(padding:const EdgeInsets.all(5),decoration:BoxDecoration(color:Colors.black.withValues(alpha:.62),shape:BoxShape.circle),child:Icon(icon,color:Colors.white,size:16))));}
}
class _MediaItem{final Photo? cloud;final LocalMedia? local;final bool alsoLocal;const _MediaItem._({this.cloud,this.local,this.alsoLocal=false});factory _MediaItem.cloud(Photo photo,{required bool alsoLocal})=>_MediaItem._(cloud:photo,alsoLocal:alsoLocal);factory _MediaItem.local(LocalMedia media)=>_MediaItem._(local:media);bool get isCloud=>cloud!=null;DateTime get date=>isCloud?DateTime.parse(cloud!.uploadedAt).toLocal():local!.createdAt;}
