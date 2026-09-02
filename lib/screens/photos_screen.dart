import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import '../models/album.dart';
import '../models/local_media.dart';
import '../models/photo.dart';
import '../services/api_service.dart';
import '../widgets/photo_thumbnail.dart';
import 'photo_viewer_screen.dart';
import 'trash_screen.dart';
import 'upload_photos_screen.dart';

class PhotosScreen extends StatefulWidget {
  final String token;
  const PhotosScreen({super.key, required this.token});
  @override State<PhotosScreen> createState()=>_PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen>{
  final ApiService _apiService=ApiService();
  final GlobalKey _gridKey=GlobalKey();
  final Map<String,GlobalKey> _mediaTileKeys={};
  final Map<DateTime,GlobalKey> _headerKeys={};
  List<Photo> _cloudPhotos=[];
  List<LocalMedia> _localMedia=[];
  Map<DateTime,List<_MediaItem>> _mediaGroups={};
  bool _isLoading=true,_hasLocalPermission=false,_isPinching=false,_pinchDirectionLocked=false,_isSelectionMode=false,_isActionRunning=false,_fastScrolling=false;
  bool _isLoadingMoreLocal=false,_hasMoreLocal=false;
  String? _errorMessage;
  int _crossAxisCount=3,_localStart=0,_localTotal=0;
  static const int _localPageSize=500;
  static const double _loadMoreThreshold=1400;
  final ScrollController _scrollController=ScrollController();
  final Map<int,Offset> _pointers={};
  double? _pinchStartDistance;
  int _pinchStartColumns=3;
  double _lastPinchRatio=1;
  static const double _pinchThreshold=.10;
  int _pinchAnchorVersion=0;
  final Set<String> _selectedKeys={};
  final ValueNotifier<double> _fastScrollFraction=ValueNotifier(0);
  final ValueNotifier<DateTime?> _fastScrollDate=ValueNotifier(null);
  static const double _headerExtent=46;
  static const double _fastThumbHeight=72;

  @override void initState(){super.initState();_apiService.setToken(widget.token);_scrollController.addListener(_onScroll);_loadMedia();}
  @override void dispose(){_scrollController.removeListener(_onScroll);_scrollController.dispose();_fastScrollFraction.dispose();_fastScrollDate.dispose();super.dispose();}

  void _onScroll(){
    _syncFastScrollbar();
    if(_isPinching||!_hasMoreLocal||_isLoadingMoreLocal||!_scrollController.hasClients)return;
    final position=_scrollController.position;
    if(position.maxScrollExtent-position.pixels<=_loadMoreThreshold)_loadMoreLocal();
  }
  void _syncFastScrollbar(){
    if(!_scrollController.hasClients||_fastScrolling)return;
    final max=_scrollController.position.maxScrollExtent;
    final double f=max<=0?0.0:(_scrollController.offset/max).clamp(0.0,1.0).toDouble();
    if((f-_fastScrollFraction.value).abs()>.002)_fastScrollFraction.value=f;
  }

  Future<void> _loadMedia()async{
    try{
      final cloudFuture=_apiService.getPhotos();
      final permission=await PhotoManager.requestPermissionExtend();
      if(!permission.hasAccess){
        final cloud=await cloudFuture;
        if(!mounted)return;
        setState((){_cloudPhotos=cloud;_localMedia=[];_mediaGroups=_buildGroups(cloud,[]);_hasLocalPermission=false;_hasMoreLocal=false;_isLoading=false;_errorMessage=null;});
        return;
      }
      final countFuture=PhotoManager.getAssetCount(type:RequestType.common);
      final cloud=await cloudFuture;
      final total=await countFuture;
      final firstEnd=math.min(_localPageSize,total);
      final firstPage=firstEnd>0?await PhotoManager.getAssetListRange(start:0,end:firstEnd,type:RequestType.common):<AssetEntity>[];
      final local=_convertAssets(firstPage);
      final groups=_buildGroups(cloud,local);
      if(!mounted)return;
      setState((){_cloudPhotos=cloud;_localMedia=local;_localStart=firstPage.length;_localTotal=total;_hasMoreLocal=_localStart<_localTotal;_mediaGroups=groups;_hasLocalPermission=true;_isLoading=false;_errorMessage=null;});
    }catch(_){if(!mounted)return;setState((){_isLoading=false;_errorMessage='Failed to load photos.';});}
  }

  List<LocalMedia> _convertAssets(List<AssetEntity> assets)=>[
    for(final asset in assets) if(!asset.isTrashed)LocalMedia(asset:asset,filename:asset.title??'')
  ];

  Future<void> _loadMoreLocal()async{
    if(!_hasLocalPermission||!_hasMoreLocal||_isLoadingMoreLocal)return;
    setState(()=>_isLoadingMoreLocal=true);
    try{
      final end=math.min(_localStart+_localPageSize,_localTotal);
      final page=await PhotoManager.getAssetListRange(start:_localStart,end:end,type:RequestType.common);
      if(page.isEmpty){if(mounted)setState(()=>_hasMoreLocal=false);return;}
      final newLocal=_convertAssets(page);
      final merged=[..._localMedia,...newLocal];
      final groups=_buildGroups(_cloudPhotos,merged);
      if(!mounted)return;
      setState((){_localMedia=merged;_localStart+=page.length;_hasMoreLocal=_localStart<_localTotal;_mediaGroups=groups;});
    }catch(_){
      // Keep the already visible library usable. A later scroll can retry.
    }finally{if(mounted)setState(()=>_isLoadingMoreLocal=false);}
  }

  Map<DateTime,List<_MediaItem>> _buildGroups(List<Photo> cloud,List<LocalMedia> local){
    final items=<_MediaItem>[];
    final localNames={for(final i in local)if(i.filename.isNotEmpty)i.filename.trim().toLowerCase()};
    for(final p in cloud)items.add(_MediaItem.cloud(p,alsoLocal:localNames.contains(p.originalFilename.trim().toLowerCase())));
    final cloudNames={for(final p in cloud)p.originalFilename.trim().toLowerCase()};
    for(final i in local)if(i.filename.isEmpty||!cloudNames.contains(i.filename.trim().toLowerCase()))items.add(_MediaItem.local(i));
    items.sort((a,b)=>b.date.compareTo(a.date));
    final groups=<DateTime,List<_MediaItem>>{};
    for(final i in items){final d=i.date;final k=DateTime(d.year,d.month,d.day);groups.putIfAbsent(k,()=>[]).add(i);}
    return groups;
  }
  Future<void> _refresh()async=>_loadMedia();

  GlobalKey _tileKeyFor(_MediaItem item){
    final key=_keyFor(item);
    return _mediaTileKeys.putIfAbsent(key,()=>GlobalKey());
  }
  GlobalKey _headerKeyFor(DateTime date)=>_headerKeys.putIfAbsent(date,()=>GlobalKey());

  Offset _pinchMidpointGlobal(){
    if(_pointers.length<2)return Offset.zero;
    final values=_pointers.values.toList();
    return Offset((values[0].dx+values[1].dx)/2,(values[0].dy+values[1].dy)/2);
  }

  Offset _pinchViewport(){
    final midpoint=_pinchMidpointGlobal();
    final renderBox=_gridKey.currentContext?.findRenderObject();
    if(renderBox is RenderBox)return renderBox.globalToLocal(midpoint);
    return Offset.zero;
  }

  _Anchor _captureAnchorAtViewport(Offset viewport){
    if(!_scrollController.hasClients)return const _Anchor(null,null,0);
    final contentY=_scrollController.offset+viewport.dy;
    final width=MediaQuery.sizeOf(context).width;
    final tile=(width-4-2*(_crossAxisCount-1))/_crossAxisCount;
    const spacing=2.0;
    var cursor=0.0;
    final dates=_mediaGroups.keys.toList()..sort((a,b)=>b.compareTo(a));
    final midpointGlobal=_pinchMidpointGlobal();
    for(final date in dates){
      final list=_mediaGroups[date]!;
      final rows=(list.length/_crossAxisCount).ceil();
      final rowHeight=tile+spacing;
      final groupHeight=_headerExtent+rows*rowHeight;
      final groupOffset=contentY-cursor;
      if(groupOffset<groupHeight){
        if(groupOffset<_headerExtent){
          return _Anchor(null,date,groupOffset.clamp(0.0,_headerExtent).toDouble(),isHeader:true,renderKey:_headerKeyFor(date),globalPoint:midpointGlobal);
        }
        if(list.isEmpty)return _Anchor(null,date,groupOffset.clamp(0.0,groupHeight).toDouble(),globalPoint:midpointGlobal);
        final gridY=groupOffset-_headerExtent;
        final row=math.min(rows-1,math.max(0,(gridY/rowHeight).floor()));
        final gridX=(viewport.dx-2).clamp(0.0,math.max(0.0,width-4)).toDouble();
        final column=math.min(_crossAxisCount-1,math.max(0,(gridX/(tile+spacing)).floor()));
        final index=math.min(row*_crossAxisCount+column,list.length-1);
        final fallbackOffset=(gridY-row*rowHeight).clamp(0.0,tile).toDouble();
        final item=list[index];
        final key=_tileKeyFor(item);
        final renderObject=key.currentContext?.findRenderObject();
        double offset=fallbackOffset;
        if(renderObject is RenderBox)offset=midpointGlobal.dy-renderObject.localToGlobal(Offset.zero).dy;
        return _Anchor(_keyFor(item),date,offset,renderKey:key,globalPoint:midpointGlobal);
      }
      cursor+=groupHeight;
    }
    return const _Anchor(null,null,0);
  }

  double _contentOffsetForAnchor(_Anchor anchor,int columns){
    if(anchor.date==null)return 0;
    final width=MediaQuery.sizeOf(context).width;
    final tile=(width-4-2*(columns-1))/columns;
    const spacing=2.0;
    var cursor=0.0;
    final dates=_mediaGroups.keys.toList()..sort((a,b)=>b.compareTo(a));
    for(final date in dates){
      final list=_mediaGroups[date]!;
      final rows=(list.length/columns).ceil();
      final rowHeight=tile+spacing;
      final groupHeight=_headerExtent+rows*rowHeight;
      if(anchor.date==date){
        if(anchor.isHeader)return cursor+anchor.offset;
        if(anchor.itemKey!=null){
          final index=list.indexWhere((item)=>_keyFor(item)==anchor.itemKey);
          if(index>=0){
            final row=index~/columns;
            return cursor+_headerExtent+row*rowHeight+anchor.offset;
          }
        }
        return cursor+anchor.offset;
      }
      cursor+=groupHeight;
    }
    return cursor;
  }

  void _correctPinchAnchor(_Anchor anchor,int columns,int version){
    if(version!=_pinchAnchorVersion||!mounted||!_scrollController.hasClients||anchor.date==null)return;
    final key=anchor.renderKey;
    final renderObject=key?.currentContext?.findRenderObject();
    if(renderObject is RenderBox){
      final newTop=renderObject.localToGlobal(Offset.zero).dy;
      final desiredTop=anchor.globalPoint.dy-anchor.offset;
      final delta=newTop-desiredTop;
      final position=_scrollController.position;
      final target=(_scrollController.offset+delta).clamp(0.0,position.maxScrollExtent).toDouble();
      if((target-_scrollController.offset).abs()>.1)_scrollController.jumpTo(target);
      return;
    }
    final contentTarget=_contentOffsetForAnchor(anchor,columns);
    final viewport=_pinchViewport();
    final target=(contentTarget-viewport.dy).clamp(0.0,_scrollController.position.maxScrollExtent).toDouble();
    if((target-_scrollController.offset).abs()>.1)_scrollController.jumpTo(target);
  }

  void _schedulePinchCorrection(_Anchor anchor,int columns,int version){
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(version!=_pinchAnchorVersion||!mounted)return;
      _correctPinchAnchor(anchor,columns,version);
      WidgetsBinding.instance.addPostFrameCallback((_){
        if(version!=_pinchAnchorVersion||!mounted)return;
        _correctPinchAnchor(anchor,columns,version);
      });
    });
  }

  void _pointerDown(PointerDownEvent e){
    _pointers[e.pointer]=e.position;
    if(_pointers.length==2){
      _pinchStartDistance=_distanceBetweenPointers();
      _pinchStartColumns=_crossAxisCount;
      _lastPinchRatio=1;
      _pinchDirectionLocked=false;
      setState(()=>_isPinching=true);
    }
  }

  void _pointerMove(PointerMoveEvent e){
    if(!_pointers.containsKey(e.pointer))return;
    _pointers[e.pointer]=e.position;
    if(!_isPinching||_pointers.length!=2||_pinchStartDistance==null)return;
    final d=_distanceBetweenPointers();
    if(d<=0)return;
    final ratio=_pinchStartDistance!/d;
    if(!_pinchDirectionLocked){
      if((ratio-1).abs()<_pinchThreshold)return;
      _pinchDirectionLocked=true;
    }
    if((_lastPinchRatio-ratio).abs()<.025)return;
    _lastPinchRatio=ratio;
    final next=(_pinchStartColumns*ratio).round().clamp(2,6);
    if(next==_crossAxisCount)return;
    final viewport=_pinchViewport();
    final anchor=_captureAnchorAtViewport(viewport);
    final version=++_pinchAnchorVersion;
    if(_scrollController.hasClients&&anchor.date!=null){
      final predictedContentOffset=_contentOffsetForAnchor(anchor,next);
      final predictedTarget=(predictedContentOffset-viewport.dy).clamp(0.0,_scrollController.position.maxScrollExtent).toDouble();
      if((predictedTarget-_scrollController.offset).abs()>.1)_scrollController.jumpTo(predictedTarget);
    }
    setState(()=>_crossAxisCount=next);
    _schedulePinchCorrection(anchor,next,version);
  }

  void _pointerUp(PointerEvent e){
    _pointers.remove(e.pointer);
    if(_pointers.length<2&&_isPinching){
      _pinchStartDistance=null;
      _pinchDirectionLocked=false;
      setState(()=>_isPinching=false);
      WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)_onScroll();});
    }
  }
  double _distanceBetweenPointers(){if(_pointers.length<2)return 0;final v=_pointers.values.toList();final dx=v[0].dx-v[1].dx,dy=v[0].dy-v[1].dy;return math.sqrt(dx*dx+dy*dy);}

  void _fastScrollToFraction(double fraction){
    if(!_scrollController.hasClients)return;
    final double f=fraction.clamp(0.0,1.0).toDouble();
    final max=_scrollController.position.maxScrollExtent;
    _scrollController.jumpTo((f*max).clamp(0.0,max));
    final dates=_mediaGroups.keys.toList()..sort((a,b)=>b.compareTo(a));
    if(dates.isNotEmpty){final idx=((dates.length-1)*f).round();_fastScrollDate.value=dates[idx];}
  }
  String _dateLabel(DateTime date){final now=DateTime.now(),today=DateTime(now.year,now.month,now.day),yesterday=today.subtract(const Duration(days:1));if(date==today)return'Today';if(date==yesterday)return'Yesterday';const m=['January','February','March','April','May','June','July','August','September','October','November','December'];return date.year==today.year?'${m[date.month-1]} ${date.day}':'${m[date.month-1]} ${date.day}, ${date.year}';}
  String _keyFor(_MediaItem i)=>i.isCloud?'cloud:${i.cloud!.id}':'local:${i.local!.asset.id}';
  bool _isSelected(_MediaItem i)=>_selectedKeys.contains(_keyFor(i));
  List<Photo> get _selectedCloudPhotos=>[for(final p in _cloudPhotos)if(_selectedKeys.contains('cloud:${p.id}'))p];
  void _enterSelection(_MediaItem i){if(_isPinching)return;setState((){_isSelectionMode=true;_selectedKeys.add(_keyFor(i));});}
  void _toggleSelection(_MediaItem i){final k=_keyFor(i);setState((){if(_selectedKeys.contains(k))_selectedKeys.remove(k);else _selectedKeys.add(k);if(_selectedKeys.isEmpty)_isSelectionMode=false;});}
  void _handleTap(_MediaItem i){if(_isSelectionMode)_toggleSelection(i);else if(i.isCloud)_openCloudPhoto(i.cloud!);else _openLocalPhoto(i.local!);}
  void _clearSelection(){setState((){_selectedKeys.clear();_isSelectionMode=false;});}
  void _selectAll(){final all=[for(final l in _mediaGroups.values)...l];final allSelected=all.isNotEmpty&&_selectedKeys.length==all.length;setState((){_isSelectionMode=true;_selectedKeys.clear();if(!allSelected)_selectedKeys.addAll(all.map(_keyFor));});}

  Future<void> _moveSelectedToTrash()async{final selected=_selectedCloudPhotos;if(selected.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Only cloud photos can be moved to Trash.')));return;}final c=selected.length,t=_selectedKeys.length;final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Move to Trash?'),content:Text('Move $c cloud ${c==1?'photo':'photos'} out of $t selected ${t==1?'file':'files'} to Trash? You can restore them for 30 days.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Move to Trash'))]));if(ok!=true)return;setState(()=>_isActionRunning=true);var s=0,f=0;for(final p in selected){try{await _apiService.movePhotoToTrash(p.id);s++;}catch(_){f++;}}if(!mounted)return;setState(()=>_isActionRunning=false);_clearSelection();await _refresh();if(!mounted)return;ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(f==0?'$s photo${s==1?'':'s'} moved to Trash.':'$s moved, $f failed.')));}
  Future<void> _addSelectedToAlbum()async{final selected=_selectedCloudPhotos;if(selected.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Only cloud photos can be added to albums.')));return;}setState(()=>_isActionRunning=true);List<Album> albums;try{albums=await _apiService.getAlbums();}catch(e){if(!mounted)return;setState(()=>_isActionRunning=false);ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Failed to load albums: $e')));return;}if(!mounted)return;setState(()=>_isActionRunning=false);if(albums.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('No albums available.')));return;}final album=await showDialog<Album>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Add to album'),content:SizedBox(width:double.maxFinite,height:math.min(360,albums.length*56.0),child:ListView.builder(itemCount:albums.length,itemBuilder:(_,i){final a=albums[i];return ListTile(leading:const Icon(Icons.photo_album_outlined),title:Text(a.name),onTap:()=>Navigator.pop(ctx,a));})),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel'))]));if(album==null||!mounted)return;setState(()=>_isActionRunning=true);var added=0,already=0,failed=0;for(final p in selected){try{await _apiService.addPhotoToAlbum(album.id,p.id);added++;}catch(e){if(e.toString().contains('409'))already++;else failed++;}}if(!mounted)return;setState(()=>_isActionRunning=false);_clearSelection();ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(failed==0&&already==0?'$added photo${added==1?'':'s'} added to "${album.name}".':'$added added, $already already there, $failed failed.')));}
  void _openCloudPhoto(Photo p)=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>PhotoViewerScreen(photos:_cloudPhotos,localMedia:_localMedia,initialIndex:_cloudPhotos.indexOf(p),token:widget.token)));
  void _openLocalPhoto(LocalMedia m)=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>PhotoViewerScreen(photos:_cloudPhotos,localMedia:_localMedia,initialIndex:0,initialLocalAsset:m.asset,token:widget.token)));
  Future<void> _openTrash()async{await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>TrashScreen(token:widget.token)));if(mounted)await _refresh();}
  Future<void> _openUploadPhotos()async{final uploaded=await Navigator.of(context).push<bool>(MaterialPageRoute(builder:(_)=>UploadPhotosScreen(token:widget.token)));if(uploaded==true&&mounted)await _refresh();}

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(
      leading:_isSelectionMode?IconButton(icon:const Icon(Icons.close),onPressed:_clearSelection):null,
      title:_isSelectionMode?Text('${_selectedKeys.length} selected'):const Text('Photos'),
      actions:_isSelectionMode?[
        if(_isActionRunning)const Padding(padding:EdgeInsets.symmetric(horizontal:16),child:Center(child:SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)))),
        if(!_isActionRunning)IconButton(tooltip:'Select all',icon:const Icon(Icons.select_all),onPressed:_selectAll),
        if(!_isActionRunning)IconButton(tooltip:'Add to album',icon:const Icon(Icons.add_to_photos_outlined),onPressed:_addSelectedToAlbum),
        if(!_isActionRunning)IconButton(tooltip:'Move cloud photos to Trash',icon:const Icon(Icons.delete_outline),onPressed:_moveSelectedToTrash)
      ]:[
        IconButton(tooltip:'Refresh',icon:const Icon(Icons.refresh),onPressed:_refresh),
        IconButton(tooltip:'Trash',icon:const Icon(Icons.delete_outline),onPressed:_openTrash)
      ]
    ),
    floatingActionButton:_isSelectionMode?null:FloatingActionButton(heroTag:'photos_upload_fab',onPressed:_openUploadPhotos,child:const Icon(Icons.add)),
    body:_buildBody()
  );

  Widget _buildBody(){
    if(_isLoading)return const Center(child:CircularProgressIndicator());
    if(_errorMessage!=null)return Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text(_errorMessage!),const SizedBox(height:16),FilledButton(onPressed:_loadMedia,child:const Text('Retry'))]));
    if(!_hasLocalPermission&&_cloudPhotos.isEmpty)return const Center(child:Text('Allow photo access to see your device media.'));
    final dates=_mediaGroups.keys.toList()..sort((a,b)=>b.compareTo(a));
    return Listener(behavior:HitTestBehavior.translucent,onPointerDown:_pointerDown,onPointerMove:_pointerMove,onPointerUp:_pointerUp,onPointerCancel:_pointerUp,child:Stack(children:[
      RefreshIndicator(onRefresh:_refresh,child:CustomScrollView(key:_gridKey,controller:_scrollController,physics:_isPinching?const NeverScrollableScrollPhysics():const AlwaysScrollableScrollPhysics(),slivers:[
        if(!_hasLocalPermission)const SliverToBoxAdapter(child:Padding(padding:EdgeInsets.fromLTRB(12,10,12,0),child:Text('Device photos are hidden until photo access is allowed.'))),
        for(final date in dates)...[
          SliverToBoxAdapter(key:_headerKeyFor(date),child:SizedBox(height:_headerExtent,child:Padding(padding:const EdgeInsets.fromLTRB(12,14,12,8),child:Text(_dateLabel(date),style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w600))))),
          SliverPadding(padding:const EdgeInsets.symmetric(horizontal:2),sliver:SliverGrid(delegate:SliverChildBuilderDelegate((context,index)=>_buildMediaTile(_mediaGroups[date]![index]),childCount:_mediaGroups[date]!.length),gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:_crossAxisCount,crossAxisSpacing:2,mainAxisSpacing:2,childAspectRatio:1)))
        ],
        if(_isLoadingMoreLocal)const SliverToBoxAdapter(child:Padding(padding:EdgeInsets.all(18),child:Center(child:SizedBox(width:22,height:22,child:CircularProgressIndicator(strokeWidth:2))))),
        const SliverToBoxAdapter(child:SizedBox(height:24))
      ])),
      Positioned(
        right:0,
        top:0,
        bottom:0,
        width:44,
        child:LayoutBuilder(
          builder:(context,box){
            final track=box.maxHeight;
            final travel=math.max(1.0,track-_fastThumbHeight);
            return ValueListenableBuilder<double>(
              valueListenable:_fastScrollFraction,
              builder:(context,fraction,_){
                final thumbTop=fraction*travel;
                return GestureDetector(
                  behavior:HitTestBehavior.translucent,
                  onVerticalDragStart:(_){setState(()=>_fastScrolling=true);},
                  onVerticalDragUpdate:(d){
                    final double f=((d.localPosition.dy-_fastThumbHeight/2)/travel).clamp(0.0,1.0).toDouble();
                    _fastScrollToFraction(f);
                  },
                  onVerticalDragEnd:(_){setState(()=>_fastScrolling=false);},
                  child:Stack(children:[
                    Positioned(top:thumbTop,right:6,child:Container(width:7,height:_fastThumbHeight,decoration:BoxDecoration(color:Theme.of(context).colorScheme.onSurface.withValues(alpha:.55),borderRadius:BorderRadius.circular(8)))),
                  ]),
                );
              },
            );
          },
        ),
      ),
      ValueListenableBuilder<DateTime?>(valueListenable:_fastScrollDate,builder:(context,date,_){if(!_fastScrolling||date==null)return const SizedBox.shrink();return Positioned(right:50,top:MediaQuery.sizeOf(context).height*.42,child:Material(color:Colors.black87,borderRadius:BorderRadius.circular(10),child:Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:8),child:Text(_dateLabel(date),style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w600)))));})
    ]));
  }

  Widget _buildMediaTile(_MediaItem item){
    final selected=_isSelected(item);
    Widget image;
    if(item.isCloud)image=PhotoThumbnail(photo:item.cloud!,token:widget.token);
    else{final l=item.local!;image=Stack(fit:StackFit.expand,children:[AssetEntityImage(l.asset,isOriginal:false,thumbnailSize:const ThumbnailSize.square(240),thumbnailFormat:ThumbnailFormat.jpeg,fit:BoxFit.cover),if(l.isVideo)const Positioned(right:8,bottom:8,child:Icon(Icons.play_circle_fill,color:Colors.white,size:28))]);}
    return KeyedSubtree(key:_tileKeyFor(item),child:GestureDetector(onTap:()=>_handleTap(item),onLongPress:()=>_enterSelection(item),child:Stack(fit:StackFit.expand,children:[image,if(item.isCloud)_buildStatusBadge(local:item.alsoLocal,cloud:true)else _buildStatusBadge(local:true,cloud:item.local!.alsoInCloud),if(selected)Container(color:Theme.of(context).colorScheme.primary.withValues(alpha:.38),child:Align(alignment:Alignment.topLeft,child:Container(margin:const EdgeInsets.all(6),decoration:BoxDecoration(color:Theme.of(context).colorScheme.primary,shape:BoxShape.circle),padding:const EdgeInsets.all(2),child:const Icon(Icons.check,color:Colors.white,size:18))))])));
  }
  Widget _buildStatusBadge({required bool local,required bool cloud}){final icon=local&&cloud?Icons.cloud_done:cloud?Icons.cloud_done:Icons.smartphone;final label=local&&cloud?'On device + cloud':cloud?'Cloud':'On device';return Positioned(top:5,right:5,child:Tooltip(message:label,child:Container(padding:const EdgeInsets.all(5),decoration:BoxDecoration(color:Colors.black.withValues(alpha:.62),shape:BoxShape.circle),child:Icon(icon,color:Colors.white,size:16))));}
}

class _Anchor{
  final String? itemKey;
  final DateTime? date;
  final double offset;
  final bool isHeader;
  final GlobalKey? renderKey;
  final Offset globalPoint;
  const _Anchor(this.itemKey,this.date,this.offset,{this.isHeader=false,this.renderKey,this.globalPoint=Offset.zero});
}

class _MediaItem{final Photo? cloud;final LocalMedia? local;final bool alsoLocal;const _MediaItem._({this.cloud,this.local,this.alsoLocal=false});factory _MediaItem.cloud(Photo p,{required bool alsoLocal})=>_MediaItem._(cloud:p,alsoLocal:alsoLocal);factory _MediaItem.local(LocalMedia m)=>_MediaItem._(local:m);bool get isCloud=>cloud!=null;DateTime get date=>isCloud?DateTime.parse(cloud!.uploadedAt).toLocal():local!.createdAt;}
