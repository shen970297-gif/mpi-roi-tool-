classdef mpi_roi_app < handle
    %MPI_ROI_APP Interactive 2-D MPI ROI analysis for DICOM/TIFF.
    % app=mpi_roi_app; or app=mpi_roi_app(folderOrFile);
    properties
        Figure
        Axes
        ImageHandle
        ColorbarHandle
        FileList
        FileListRows = gobjects(0)
        FileListBackground
        FileListHighlight
        FileListDropLine
        FileListScroll
        FileListTop = 1
        FileDrag = []
        RoiList
        RoiPanel
        RoiScroll
        RoiRows = {}
        ResultTable
        TimeAxes
        TimeMetric
        TimeStatus
        TimeRoiTable
        HiddenTimeRois = strings(0,1)
        TimeLines = gobjects(0)
        TimeNames = strings(0,1)
        TimeCurveKeys = strings(0,1)
        TimeSeries = struct('Key',{},'Animal',{},'Label',{},'Files',{},'Minutes',{})
        ActiveTimeSeries = ''
        TimeColors
        TimepointCache
        LastDragUpdate = []
        ROIColors
        CurrentStatistics = table()
        CurrentMasks = {}
        IsDrawingROI = false
        Status
        InfoText
        LowEdit
        HighEdit
        DisplayLimits = []
        ScaleText
        PhysicalPixelsPerMm = NaN
        ThresholdMode = 'background'
        ThresholdK = 2
        FixedThreshold = 0
        KEdit
        FixedEdit
        Data = []
        Meta = struct()
        File = ''
        Files = {}
        Root = ''
        ROIs = struct('Name',{},'Shape',{},'Handle',{},'Listeners',{})
        Background = 0
        Cache
        Dirty = false
        ROIClipboard = struct([])
        ROIBatchClipboard = struct([])
    end
    methods
        function app=mpi_roi_app(startPath,visible)
            if nargin<1 || isempty(startPath)
                startPath='D:\实测数据_商用MPI\20260904_大鼠脑脊液\20260904bigmouse\20260904bigmouse';
            end
            if nargin<2, visible='on'; end
            if exist('drawpolygon','file')~=2 || exist('dicomread','file')~=2
                error('MPI:Toolbox','Requires MATLAB and Image Processing Toolbox.');
            end
            app.Cache=containers.Map('KeyType','char','ValueType','any');
            app.ROIColors=containers.Map('KeyType','char','ValueType','any');
            app.TimeColors=containers.Map('KeyType','char','ValueType','any');
            app.TimepointCache=containers.Map('KeyType','char','ValueType','any');
            screen=get(groot,'ScreenSize');
            windowSize=min([1380 820],max([1 1],screen(3:4)-[80 125]));
            windowOrigin=screen(1:2)+min([69 79],floor((screen(3:4)-windowSize)/2));
            app.Figure=figure('Name','MPI ROI 定量分析','NumberTitle','off', ...
                'MenuBar','none','ToolBar','figure','Units','pixels','Position',[windowOrigin windowSize], ...
                'Color',[.96 .97 .98],'Visible','off','CloseRequestFcn',@(~,~)app.closeApp(), ...
                'WindowScrollWheelFcn',@(~,event)app.scrollLists(event), ...
                'WindowKeyPressFcn',@(~,event)app.fileListKey(event));
            if isprop(app.Figure,'AutoResizeChildren'), app.Figure.AutoResizeChildren='off'; end
            z=zoom(app.Figure);
            set(z,'ActionPostCallback',@(~,~)app.capturePhysicalScale());
            app.button('选择数据文件夹',[.015 .94 .13 .04],@()app.pickFolder());
            app.button('打开单个图像',[.15 .94 .13 .04],@()app.pickFile());
            app.button('导出全部数据',[.33 .94 .16 .04],@()app.exportAllResults());
            app.ScaleText=uicontrol(app.Figure,'Style','text','Units','normalized', ...
                'Position',[.50 .94 .18 .035],'HorizontalAlignment','left', ...
                'String','物理比例：未标定');
            app.button('平移',[.69 .94 .055 .04],@()app.togglePan());
            app.button('重设比例',[.75 .94 .065 .04],@()app.resetPhysicalScale());
            app.createFileList();
            app.InfoText=uicontrol(app.Figure,'Style','text','Units','normalized', ...
                'Position',[.015 .07 .265 .14],'HorizontalAlignment','left','FontSize',9);
            uicontrol(app.Figure,'Style','text','Units','normalized','Position',[.015 .35 .26 .025], ...
                'String','阈值设置','HorizontalAlignment','left','FontWeight','bold');
            uicontrol(app.Figure,'Style','radiobutton','Units','normalized','Position',[.015 .32 .26 .03], ...
                'String','背景均值 + k × SD','Value',1,'Tag','threshold_background', ...
                'Callback',@(~,~)app.safe(@()app.setThresholdMode('background')));
            uicontrol(app.Figure,'Style','text','Units','normalized','Position',[.015 .285 .06 .03], ...
                'String','k','HorizontalAlignment','left');
            app.KEdit=uicontrol(app.Figure,'Style','edit','Units','normalized','Position',[.20 .285 .075 .03], ...
                'String','2.0','Callback',@(~,~)app.safe(@()app.thresholdChanged()));
            uicontrol(app.Figure,'Style','radiobutton','Units','normalized','Position',[.015 .25 .26 .03], ...
                'String','固定 MPI 阈值','Value',0,'Tag','threshold_fixed', ...
                'Callback',@(~,~)app.safe(@()app.setThresholdMode('fixed')));
            uicontrol(app.Figure,'Style','text','Units','normalized','Position',[.015 .215 .13 .03], ...
                'String','固定阈值','HorizontalAlignment','left');
            app.FixedEdit=uicontrol(app.Figure,'Style','edit','Units','normalized','Position',[.20 .215 .075 .03], ...
                'String','0.0','Callback',@(~,~)app.safe(@()app.thresholdChanged()));
            app.Axes=axes('Parent',app.Figure,'Units','normalized','Position',[.33 .475 .44 .425]);
            disableDefaultInteractivity(app.Axes); % Zoom only through the tracked toolbar mode.
            app.createRoiPanel();
            uicontrol(app.Figure,'Style','text','Units','normalized','Position',[.32 .421 .10 .025], ...
                'String','显示下限 / 上限');
            app.LowEdit=uicontrol(app.Figure,'Style','edit','Units','normalized','Position',[.42 .415 .09 .035],'String','0');
            app.HighEdit=uicontrol(app.Figure,'Style','edit','Units','normalized','Position',[.52 .415 .09 .035],'String','1');
            applyRange=app.button('应用显示范围',[.62 .415 .11 .035],@()app.applyLimits());
            applyRange.TooltipString='应用上下限，后续图像沿用。';
            autoRange=app.button('自动范围',[.74 .415 .08 .035],@()app.autoLimits());
            autoRange.TooltipString='按当前图计算范围，后续图像沿用。';
            app.ResultTable=uitable(app.Figure,'Units','normalized','Position',[.305 .318 .68 .083], ...
                'RowName',[],'FontSize',10);
            app.TimeAxes=axes('Parent',app.Figure,'Units','normalized','Position',[.365 .105 .370 .151]);
            disableDefaultInteractivity(app.TimeAxes);
            app.TimeRoiTable=uitable(app.Figure,'Units','normalized','Position',[.760 .070 .225 .186], ...
                'RowName',[],'FontSize',9,'ColumnName',{'显示','动物 · ROI'}, ...
                'ColumnFormat',{'logical','char'},'ColumnEditable',[true false],'Data',cell(0,2), ...
                'TooltipString','可同时勾选不同动物的 ROI 曲线。', ...
                'CellEditCallback',@(~,event)app.safe(@()app.setTimeRoiShown(event)));
            app.layoutTimeRoiTable();
            app.TimeStatus=uicontrol(app.Figure,'Style','text','Units','normalized', ...
                'Position',[.305 .268 .48 .035],'HorizontalAlignment','left','FontSize',9);
            app.TimeMetric=uicontrol(app.Figure,'Style','popupmenu','Units','normalized', ...
                'Position',[.797 .268 .188 .035],'FontSize',9, ...
                'String',{'校正后总信号','校正后平均信号','原始总信号'}, ...
                'Callback',@(~,~)app.safe(@()app.refreshTimecourse(app.CurrentStatistics)));
            app.refreshTimecourse(app.CurrentStatistics);
            app.Status=uicontrol(app.Figure,'Style','text','Units','normalized', ...
                'Position',[.015 .015 .97 .035],'HorizontalAlignment','left','FontSize',11, ...
                'String','选择图像，然后勾画 ROI。多边形双击结束，拖动边界后自动更新统计。');
            app.Figure.SizeChangedFcn=@(~,~)app.resizeView();
            app.Figure.Visible=visible;
            if isfolder(startPath), app.scanFolder(startPath);
            elseif isfile(startPath), app.openImage(startPath); end
        end
        function createFileList(app)
            panel=uipanel(app.Figure,'Units','normalized','Position',[.015 .38 .265 .55], ...
                'Title','数据列表（拖动排序）','BackgroundColor',[1 1 1]);
            app.FileList=axes('Parent',panel,'Units','normalized','Position',[.012 .015 .925 .970], ...
                'Visible','off','XLim',[0 1],'YLim',[0 1],'YDir','reverse');
            ax=app.FileList;
            disableDefaultInteractivity(ax);
            ax.Toolbar.Visible='off';
            setAllowAxesZoom(zoom(app.Figure),ax,false);
            setAllowAxesPan(pan(app.Figure),ax,false);
            app.FileListBackground=patch(ax,[0 1 1 0],[0 0 1 1],[1 1 1], ...
                'EdgeColor','none','ButtonDownFcn',@(~,~)app.beginFileDrag(app.Figure.CurrentPoint));
            app.FileListHighlight=patch(ax,[0 1 1 0],[0 0 1 1],[.81 .90 1], ...
                'EdgeColor','none','HitTest','off','PickableParts','none','Visible','off');
            app.FileListDropLine=line(ax,[0 1],[0 0],'Color',[.10 .38 .69],'LineWidth',1.75, ...
                'HitTest','off','PickableParts','none','Visible','off');
            app.FileListScroll=uicontrol(panel,'Style','slider','Units','normalized', ...
                'Position',[.943 .015 .053 .970],'Min',0,'Max',1,'Value',1,'Enable','off', ...
                'TooltipString','滚动数据列表','Callback',@(~,~)app.scrollFileSlider());
            app.layoutFileList();
        end
        function layoutFileList(app)
            bounds=getpixelposition(app.FileList);
            count=max(1,floor(bounds(4)/20));
            ax=app.FileList;
            if numel(app.FileListRows)~=count
                delete(app.FileListRows);
                ax.YLim=[0 count];
                app.FileListBackground.YData=[0 0 count count];
                app.FileListRows=gobjects(count,1);
                for k=1:count
                    app.FileListRows(k)=text(ax,.025,k-.5,'','FontSize',9,'Color',[.15 .19 .24], ...
                        'Interpreter','none','Clipping','on','HitTest','off','PickableParts','none');
                end
                uistack(app.FileListDropLine,'top');
            end
            app.renderFileList();
        end
        function renderFileList(app)
            count=numel(app.FileListRows);
            lastTop=max(1,numel(app.Files)-count+1);
            app.FileListTop=max(1,min(app.FileListTop,lastTop));
            listShown=app.FileListTop:min(numel(app.Files),app.FileListTop+count-1);
            labels=repmat({''},count,1);
            if ~isempty(listShown)
                labels(1:numel(listShown))=cellfun(@(p)p(numel(app.Root)+2:end), ...
                    app.Files(listShown),'UniformOutput',false);
            end
            set(app.FileListRows,{'String'},labels);
            chosen=find(strcmp(app.Files(listShown),app.File),1);
            if isempty(chosen)
                app.FileListHighlight.Visible='off';
            else
                app.FileListHighlight.YData=[chosen-1 chosen-1 chosen chosen];
                app.FileListHighlight.Visible='on';
            end
            scroll=app.FileListScroll;
            if lastTop>1
                scroll.Value=1-(app.FileListTop-1)/(lastTop-1);
                scroll.SliderStep=[1,min(count,lastTop-1)]/(lastTop-1);
                scroll.Enable='on';
            else
                scroll.Value=1;
                scroll.Enable='off';
            end
        end
        function scrollFileSlider(app)
            lastTop=max(1,numel(app.Files)-numel(app.FileListRows)+1);
            app.FileListTop=1+round((1-app.FileListScroll.Value)*(lastTop-1));
            app.renderFileList();
        end
        function scrollLists(app,event)
            if app.IsDrawingROI, return; end
            point=app.Figure.CurrentPoint;
            if isfinite(app.fileListOffset(point))
                app.FileListTop=app.FileListTop+3*event.VerticalScrollCount;
                app.renderFileList();
                if ~isempty(app.FileDrag), app.showFileDrop(point); end
            else
                app.wheelRoiPanel(event);
            end
        end
        function offset=fileListOffset(app,point)
            bounds=getpixelposition(app.FileList,true);
            relative=(point-bounds(1:2))./max(1,bounds(3:4));
            offset=NaN;
            if all(relative>=0 & relative<1)
                offset=(1-relative(2))*numel(app.FileListRows);
            end
        end
        function beginFileDrag(app,point)
            if app.IsDrawingROI || ~any(strcmp(app.Figure.SelectionType,{'normal','open'})), return; end
            offset=app.fileListOffset(point);
            if ~isfinite(offset) || offset>=numel(app.FileListRows), return; end
            index=app.FileListTop+floor(offset);
            if index>numel(app.Files), return; end
            if ~isempty(app.FileDrag), app.cancelFileDrag(); end
            fig=app.Figure;
            app.FileDrag=struct('Index',index,'Point',point,'Moved',false, ...
                'Motion',fig.WindowButtonMotionFcn,'Release',fig.WindowButtonUpFcn, ...
                'Press',fig.WindowButtonDownFcn,'Pointer',fig.Pointer);
            fig.WindowButtonDownFcn=@(~,~)app.cancelFileDrag();
            fig.WindowButtonMotionFcn=@(~,~)app.updateFileDrag(fig.CurrentPoint);
            fig.WindowButtonUpFcn=@(~,~)app.finishFileDrag(fig.CurrentPoint);
        end
        function updateFileDrag(app,point)
            if isempty(app.FileDrag), return; end
            if ~app.FileDrag.Moved && norm(point-app.FileDrag.Point)>=5
                app.FileDrag.Moved=true;
                app.Figure.Pointer='fleur';
            end
            if ~app.FileDrag.Moved, return; end
            offset=app.fileListOffset(point);
            if isfinite(offset)
                count=numel(app.FileListRows);
                step=double(offset>count-.6)-double(offset<.6);
                if step~=0
                    app.FileListTop=app.FileListTop+step;
                    app.renderFileList();
                end
            end
            app.showFileDrop(point);
        end
        function showFileDrop(app,point)
            offset=app.fileListOffset(point);
            guide=app.FileListDropLine;
            if app.FileDrag.Moved && isfinite(offset)
                index=min(numel(app.Files)+1,app.FileListTop+round(offset));
                guide.YData=[1 1]*(index-app.FileListTop);
                guide.Visible='on';
            else
                guide.Visible='off';
            end
        end
        function finishFileDrag(app,point)
            if isempty(app.FileDrag), return; end
            drag=app.FileDrag;
            app.cancelFileDrag();
            offset=app.fileListOffset(point);
            if ~isfinite(offset), return; end
            if drag.Moved || norm(point-drag.Point)>=5
                before=min(numel(app.Files)+1,app.FileListTop+round(offset));
                app.moveListedFile(drag.Index,before);
            elseif app.FileListTop+floor(offset)==drag.Index
                app.selectFile(drag.Index);
            end
        end
        function cancelFileDrag(app)
            if isempty(app.FileDrag), return; end
            drag=app.FileDrag;
            app.FileDrag=[];
            app.FileListDropLine.Visible='off';
            set(app.Figure,'WindowButtonMotionFcn',drag.Motion, ...
                'WindowButtonUpFcn',drag.Release,'WindowButtonDownFcn',drag.Press,'Pointer',drag.Pointer);
        end
        function moveListedFile(app,source,before)
            destination=before-double(before>source);
            if destination==source, return; end
            moved=app.Files{source};
            order=1:numel(app.Files);
            order(source)=[];
            order=[order(1:destination-1),source,order(destination:end)];
            app.Files=app.Files(order);
            app.renderFileList();
            [~,name,ext]=fileparts(moved);
            set(app.Status,'String',sprintf('已将 %s 移至列表第 %d 项。',[name ext],destination));
        end
        function fileListKey(app,event)
            if app.IsDrawingROI, return; end
            if ~isempty(app.FileDrag)
                if strcmp(event.Key,'escape'), app.cancelFileDrag(); end
                return;
            end
            item=app.Figure.CurrentObject;
            if isempty(app.Files) || isempty(item) || ...
                    ~(isequal(item,app.FileList) || isequal(ancestor(item,'axes'),app.FileList))
                return;
            end
            index=find(strcmp(app.Files,app.File),1);
            if isempty(index), index=app.FileListTop; end
            switch event.Key
                case 'uparrow', index=index-1;
                case 'downarrow', index=index+1;
                case 'home', index=1;
                case 'end', index=numel(app.Files);
                case 'pageup', index=index-numel(app.FileListRows);
                case 'pagedown', index=index+numel(app.FileListRows);
                otherwise, return;
            end
            app.selectFile(max(1,min(numel(app.Files),index)));
        end
        function createRoiPanel(app)
            app.RoiPanel=uipanel(app.Figure,'Units','normalized','Position',[.825 .410 .162 .54], ...
                'BorderType','none','BackgroundColor',app.Figure.Color);
            app.RoiScroll=uicontrol(app.RoiPanel,'Style','slider','Units','pixels', ...
                'Min',0,'Max',1,'Value',1,'TooltipString','上下滚动 ROI 功能区', ...
                'Callback',@(~,~)app.layoutRoiPanel());
            app.RoiList=uicontrol(app.RoiPanel,'Style','listbox','Units','pixels', ...
                'Position',[1 1 1 1],'FontSize',11,'String',{});
            button=@(label,fn)app.button(label,[1 1 1 1],fn,app.RoiPanel);
            export=button('导出结果',@()app.exportResults());
            export.TooltipString='导出统计、掩膜和图像';
            app.RoiRows={ ...
                [button('多边形',@()app.draw('polygon')),button('自由手绘',@()app.draw('freehand'))], ...
                [button('椭圆',@()app.draw('ellipse')),button('矩形',@()app.draw('rectangle'))], ...
                [button('复制 ROI',@()app.copyROI()),button('粘贴 ROI',@()app.pasteROI())], ...
                [button('仅移动',@()app.setROIMode('translate')),button('编辑轮廓',@()app.setROIMode('all'))], ...
                app.RoiList, ...
                [button('重命名',@()app.renameROI()),button('删除',@()app.removeROI())], ...
                [button('设为背景',@()app.setBackground()),button('取消背景',@()app.clearBackground())], ...
                [button('保存 ROI',@()app.saveROIs()),button('载入 ROI',@()app.loadROIs())], ...
                export, ...
                [button('复制全部',@()app.copyAllROIs()),button('粘贴全部',@()app.pasteAllROIs())]};
            app.layoutRoiPanel();
        end
        function resizeView(app)
            if app.IsDrawingROI, return; end
            app.fitImageAxes();
            app.layoutFileList();
            app.layoutRoiPanel();
            app.layoutTimeRoiTable();
        end
        function layoutRoiPanel(app)
            if isempty(app.RoiRows) || ~isgraphics(app.RoiPanel), return; end
            bounds=getpixelposition(app.RoiPanel);
            width=floor(bounds(3)); height=floor(bounds(4));
            edge=4; gap=5; rail=16; buttonHeight=29;
            contentWidth=max(1,width-2*edge-rail-gap);
            rows=app.RoiRows;
            if contentWidth<144, rows=num2cell([rows{:}]); end
            heights=repmat(buttonHeight,1,numel(rows));
            listRow=cellfun(@(row)isequal(row,app.RoiList),rows);
            heights(listRow)=min(78,max(buttonHeight,floor(height/3)));
            overflow=max(0,2*edge+sum(heights)+gap*(numel(rows)-1)-height);
            scroll=app.RoiScroll;
            scroll.Position=[max(1,width-edge-rail),edge,rail,max(1,height-2*edge)];
            if overflow>0
                scroll.Enable='on';
                scroll.SliderStep=[min(1,(buttonHeight+gap)/overflow),min(1,max(buttonHeight+gap,.8*height)/overflow)];
            else
                scroll.Value=1;
                scroll.Enable='off';
            end
            top=height-edge+round(overflow*(1-scroll.Value));
            for k=1:numel(rows)
                row=rows{k}; bottom=top-heights(k);
                visible='off';
                if bottom>=0 && top<=height, visible='on'; end
                controlWidth=floor((contentWidth-gap*(numel(row)-1))/numel(row));
                for j=1:numel(row)
                    left=edge+(j-1)*(controlWidth+gap);
                    set(row(j),'Position',[left,bottom,max(1,controlWidth),heights(k)],'Visible',visible);
                end
                top=bottom-gap;
            end
        end
        function wheelRoiPanel(app,event)
            if isempty(app.RoiScroll) || ~isgraphics(app.RoiScroll) || strcmp(app.RoiScroll.Enable,'off')
                return;
            end
            point=app.Figure.CurrentPoint;
            bounds=getpixelposition(app.RoiPanel,true);
            if any(point<bounds(1:2)) || any(point>bounds(1:2)+bounds(3:4)), return; end
            if strcmp(app.RoiList.Visible,'on')
                listBounds=getpixelposition(app.RoiList,true);
                if all(point>=listBounds(1:2)) && all(point<=listBounds(1:2)+listBounds(3:4)), return; end
            end
            scroll=app.RoiScroll;
            scroll.Value=max(0,min(1,scroll.Value-event.VerticalScrollCount*scroll.SliderStep(1)));
            app.layoutRoiPanel();
        end
        function h=button(app,label,pos,fn,parent)
            if nargin<5
                parent=app.Figure;
                units='normalized';
            else
                units='pixels';
            end
            h=uicontrol(parent,'Style','pushbutton','String',label,'Units',units, ...
                'Position',pos,'FontSize',10,'Callback',@(~,~)app.safe(fn));
        end
        function safe(app,fn)
            if app.IsDrawingROI, return; end
            try, fn(); catch ex
                set(app.Status,'String',ex.message);
                errordlg(ex.message,'MPI ROI');
            end
        end
        function pickFolder(app)
            p=uigetdir(app.Root,'选择扫描记录或总数据目录');
            if isequal(p,0), return; end
            app.scanFolder(p);
        end
        function scanFolder(app,p)
            d=dir(fullfile(p,'**','*.dcm'));
            d=app.excludeXZFolders(d);
            if isempty(d)
                d=[dir(fullfile(p,'**','*.tif'));dir(fullfile(p,'**','*.tiff'))];
                d=app.excludeXZFolders(d);
            end
            if isempty(d), error('MPI:Files','排除 x、z 文件夹后，没有可列出的 DICOM/TIFF 图像。'); end
            paths=arrayfun(@(x)fullfile(x.folder,x.name),d,'UniformOutput',false);
            app.Files=sort(paths); app.Root=char(p);
            app.PhysicalPixelsPerMm=NaN; % The first image in this folder sets the display scale.
            app.cancelFileDrag();
            app.FileListTop=1;
            app.openImage(app.Files{1});
        end
        function d=excludeXZFolders(~,d)
            % Match complete folder names, not letters in scan/file names.
            keep=true(size(d));
            for k=1:numel(d)
                parts=regexp(strrep(d(k).folder,'\','/'),'/','split');
                keep(k)=~any(strcmpi(parts,'x') | strcmpi(parts,'z'));
            end
            d=d(keep);
        end
        function pickFile(app)
            [f,p]=uigetfile({'*.dcm;*.tif;*.tiff','DICOM / TIFF'},'选择重建图像');
            if isequal(f,0), return; end
            app.openImage(fullfile(p,f));
        end
        function selectFile(app,index)
            if ~strcmp(app.File,app.Files{index})
                app.safe(@()app.openImage(app.Files{index}));
            end
            count=numel(app.FileListRows);
            app.FileListTop=max(index-count+1,min(app.FileListTop,index));
            app.renderFileList();
        end
        function openImage(app,file)
            [data,meta]=mpi_read_image(file); % Read first, before changing current state.
            app.stash(); app.clearGraphics();
            app.Data=data; app.Meta=meta; app.File=char(file);
            app.renderFileList();
            app.Background=0; app.Dirty=false; app.CurrentStatistics=table();
            app.CurrentMasks={}; app.LastDragUpdate=[];
            app.prepareTimecourse();
            cla(app.Axes);
            app.ImageHandle=imagesc(app.Axes,data);
            axis(app.Axes,'image'); set(app.Axes,'YDir','reverse');
            colormap(app.Axes,'turbo');
            app.ColorbarHandle=colorbar(app.Axes);
            app.fitImageAxes();
            xlabel(app.Axes,'列 / column (pixel)'); ylabel(app.Axes,'行 / row (pixel)');
            [~,name,ext]=fileparts(file); title(app.Axes,[name ext],'Interpreter','none');
            if isempty(app.DisplayLimits)
                app.autoLimits();
            else
                app.setDisplayLimits(app.DisplayLimits);
            end
            if isKey(app.Cache,app.File)
                c=app.Cache(app.File);
                if isequaln(c.Data,data)
                    app.restore(c.Definitions,c.Background); app.Dirty=c.Dirty;
                else
                    remove(app.Cache,app.File);
                end
            end
            set(app.InfoText,'String',sprintf(['%s\n\n尺寸: %d 行 × %d 列\n存储类型: %s\n' ...
                'Slope: %.12g\nIntercept: %.12g\n像素间距 [行,列]: [%.8g, %.8g] mm\n' ...
                '单位: %s\n\n当前为独立二维图像统计。'],app.File,size(data,1),size(data,2), ...
                meta.StoredClass,meta.Slope,meta.Intercept,meta.PixelSpacing,meta.Units));
            set(app.InfoText,'TooltipString',get(app.InfoText,'String'));
            app.refresh();
            if all(isfinite(meta.PixelSpacing)) && all(meta.PixelSpacing>0)
                set(app.Status,'String','物理显示比例已锁定；不同视窗按相同 mm/屏幕像素显示。较大图像可使用“平移”。');
            else
                set(app.Status,'String','当前图像无有效 PixelSpacing，仅按图像像素适配；无法保证屏幕同尺寸对应同面积。');
            end
        end
        function fitImageAxes(app)
            if isempty(app.Data) || isempty(app.Axes) || ~isgraphics(app.Axes), return; end
            [rows,cols]=size(app.Data);
            figurePosition=getpixelposition(app.Figure);
            figureWidth=figurePosition(3); figureHeight=figurePosition(4);
            if figureWidth<=0 || figureHeight<=0, return; end
            % Available image region, leaving the left/right controls intact.
            box=[.33 .475 .43 .425];
            maxWidth=box(3)*figureWidth;
            maxHeight=box(4)*figureHeight;
            spacing=app.Meta.PixelSpacing;
            hasPhysicalScale=numel(spacing)==2 && all(isfinite(spacing)) && all(spacing>0);
            if hasPhysicalScale
                if ~isfinite(app.PhysicalPixelsPerMm) || app.PhysicalPixelsPerMm<=0
                    app.PhysicalPixelsPerMm=min(maxWidth/(cols*spacing(2)), ...
                        maxHeight/(rows*spacing(1)));
                end
                scale=app.PhysicalPixelsPerMm;
                visibleCols=min(cols,maxWidth/(scale*spacing(2)));
                visibleRows=min(rows,maxHeight/(scale*spacing(1)));
                imageWidth=visibleCols*spacing(2)*scale/figureWidth;
                imageHeight=visibleRows*spacing(1)*scale/figureHeight;
                aspect=[1/spacing(2) 1/spacing(1) 1];
            else
                scale=min(maxWidth/cols,maxHeight/rows);
                visibleCols=cols; visibleRows=rows;
                imageWidth=cols*scale/figureWidth;
                imageHeight=rows*scale/figureHeight;
                aspect=[1 1 1];
            end
            imageLeft=box(1)+(box(3)-imageWidth)/2;
            imageBottom=box(2)+(box(4)-imageHeight)/2;
            centerCol=(cols+1)/2; centerRow=(rows+1)/2;
            set(app.Axes,'Units','normalized', ...
                'Position',[imageLeft imageBottom imageWidth imageHeight], ...
                'DataAspectRatio',aspect,'PlotBoxAspectRatioMode','auto', ...
                'XLim',[centerCol-visibleCols/2 centerCol+visibleCols/2], ...
                'YLim',[centerRow-visibleRows/2 centerRow+visibleRows/2]);
            if ~isempty(app.ColorbarHandle) && isgraphics(app.ColorbarHandle)
                set(app.ColorbarHandle,'Units','normalized', ...
                    'Position',[imageLeft+imageWidth+.008 imageBottom .015 imageHeight]);
            end
            if ~isempty(app.ScaleText) && isgraphics(app.ScaleText)
                if hasPhysicalScale
                    set(app.ScaleText,'String',sprintf('物理比例：%.3g 屏幕像素/mm',scale));
                else
                    set(app.ScaleText,'String','物理比例：未标定');
                end
            end
        end
        function resetPhysicalScale(app)
            if isempty(app.Data), return; end
            if ~all(isfinite(app.Meta.PixelSpacing)) || ~all(app.Meta.PixelSpacing>0)
                error('MPI:Scale','当前图像没有有效 PixelSpacing，无法锁定物理比例。');
            end
            app.PhysicalPixelsPerMm=NaN;
            app.fitImageAxes();
            set(app.Status,'String','已以当前图像重设统一物理显示比例。');
        end
        function capturePhysicalScale(app)
            if isempty(app.Data) || isempty(app.Axes) || ~isgraphics(app.Axes), return; end
            spacing=app.Meta.PixelSpacing;
            if ~all(isfinite(spacing)) || ~all(spacing>0), return; end
            axesPixels=getpixelposition(app.Axes);
            widthMm=diff(get(app.Axes,'XLim'))*spacing(2);
            if widthMm>0
                app.PhysicalPixelsPerMm=axesPixels(3)/widthMm;
                if ~isempty(app.ScaleText) && isgraphics(app.ScaleText)
                    set(app.ScaleText,'String',sprintf('物理比例：%.3g 屏幕像素/mm',app.PhysicalPixelsPerMm));
                end
            end
        end
        function autoLimits(app)
            if isempty(app.Data), return; end
            v=app.Data(isfinite(app.Data)); a=min(v); b=max(v);
            if a==b, b=a+max(1,abs(a)*.01); end
            app.setDisplayLimits([a b]);
        end
        function applyLimits(app)
            a=str2double(get(app.LowEdit,'String')); b=str2double(get(app.HighEdit,'String'));
            if ~isfinite(a) || ~isfinite(b) || a>=b, error('MPI:Limits','显示下限必须小于上限。'); end
            app.setDisplayLimits([a b]);
        end
        function setDisplayLimits(app,limits)
            caxis(app.Axes,limits);
            app.DisplayLimits=limits;
            set(app.LowEdit,'String',sprintf('%.12g',limits(1)));
            set(app.HighEdit,'String',sprintf('%.12g',limits(2)));
        end
        function setThresholdMode(app,mode)
            app.ThresholdMode=mode;
            set(findobj(app.Figure,'Tag','threshold_background'),'Value',strcmp(mode,'background'));
            set(findobj(app.Figure,'Tag','threshold_fixed'),'Value',strcmp(mode,'fixed'));
            app.thresholdChanged();
        end
        function thresholdChanged(app)
            k=str2double(get(app.KEdit,'String'));
            fixed=str2double(get(app.FixedEdit,'String'));
            if ~isfinite(k) || k<0 || ~isfinite(fixed)
                set(app.KEdit,'String',num2str(app.ThresholdK));
                set(app.FixedEdit,'String',num2str(app.FixedThreshold));
                error('MPI:Threshold','k 必须为非负有限数，固定阈值必须为有限数。');
            end
            app.ThresholdK=k; app.FixedThreshold=fixed;
            if ~isempty(app.Data), app.changed(); end
        end
        function draw(app,shape)
            if app.IsDrawingROI, return; end
            if isempty(app.Data)
                set(app.Status,'String','请先打开一张图像，再勾画 ROI。');
                return;
            end
            a=inputdlg('ROI 名称：','新建 ROI',1,{sprintf('ROI_%d',numel(app.ROIs)+1)});
            if isempty(a) || isempty(strtrim(a{1})), return; end
            figure(app.Figure);
            app.leaveNavigation();
            state=app.captureDrawingInput();
            finish=onCleanup(@()app.unlockDrawingInput(state));
            app.lockDrawingInput(state);
            switch shape
                case 'polygon'
                    message='在图像内单击添加顶点，按 Enter 或双击结束，Esc 取消。';
                case 'freehand'
                    message='在图像内按住左键沿轮廓拖动，松开完成，Esc 取消。';
                otherwise
                    message='在图像内按住左键拖出 ROI，松开完成，Esc 取消。';
            end
            set(app.Status,'String',message);
            drawnow limitrate nocallbacks;
            h=app.addROI(shape,[],strtrim(a{1}),true);
            clear finish
            if isempty(h)
                set(app.Status,'String','已取消勾画。选择形状可重新开始。');
                return;
            end
            app.refresh();
            set(app.RoiList,'Value',numel(app.ROIs));
            set(app.Status,'String',[app.Status.String ' 拖动可整体移动，改变边界前请点“编辑轮廓”。']);
        end
        function leaveNavigation(app)
            zoom(app.Figure,'off');
            pan(app.Figure,'off');
            datacursormode(app.Figure,'off');
        end
        function togglePan(app)
            mode=pan(app.Figure);
            if strcmp(mode.Enable,'on')
                app.leaveNavigation();
                set(app.Status,'String','已退出平移，可继续勾画或移动 ROI。');
            else
                app.leaveNavigation();
                pan(app.Figure,'on');
                set(app.Status,'String','正在平移图像。再点“平移”退出，选勾画形状也会退出。');
            end
        end
        function state=captureDrawingInput(app)
            state.ROIs={app.ROIs.Handle};
            state.Interactions=cellfun(@(h)h.InteractionsAllowed,state.ROIs,'UniformOutput',false);
            state.Faces=cellfun(@(h)h.FaceSelectable,state.ROIs,'UniformOutput',false);
            state.Controls=[findall(app.Figure,'Type','uicontrol','Enable','on'); ...
                findall(app.Figure,'Type','uipushtool','Enable','on'); ...
                findall(app.Figure,'Type','uitoggletool','Enable','on'); ...
                findall(app.TimeRoiTable,'Enable','on')];
            state.Toolbar=app.Axes.Toolbar;
            state.ToolbarVisibility=state.Toolbar.Visible;
            state.WindowSize=app.Figure.Position(3:4);
        end
        function lockDrawingInput(app,state)
            app.IsDrawingROI=true;
            set(state.Controls,'Enable','off');
            state.Toolbar.Visible='off';
            for k=1:numel(state.ROIs)
                h=state.ROIs{k};
                app.setRoiInteraction(h,'none');
                h.FaceSelectable=false;
            end
        end
        function unlockDrawingInput(app,state)
            app.IsDrawingROI=false;
            for k=1:numel(state.ROIs)
                h=state.ROIs{k};
                if ~isvalid(h), continue; end
                h.FaceSelectable=state.Faces{k};
                app.setRoiInteraction(h,state.Interactions{k});
            end
            set(state.Controls(isgraphics(state.Controls)),'Enable','on');
            if isvalid(state.Toolbar), state.Toolbar.Visible=state.ToolbarVisibility; end
            if isgraphics(app.Figure) && ~isequal(state.WindowSize,app.Figure.Position(3:4))
                app.resizeView();
            end
        end
        function h=addROI(app,shape,position,name,deferRefresh)
            if nargin<5, deferRefresh=false; end
            color=app.roiColor(char(name));
            args={'Color',color,'Label','','Deletable',false, ...
                'FaceAlpha',.02,'LineWidth',.8,'MarkerSize',3};
            if ~isempty(position)
                if strcmp(shape,'ellipse')
                    args=[args,{'Center',position.Center,'SemiAxes',position.SemiAxes,'RotationAngle',position.RotationAngle}];
                elseif strcmp(shape,'rectangle') && isstruct(position)
                    args=[args,{'Position',position.Position,'RotationAngle',position.RotationAngle}];
                else
                    args=[args,{'Position',position}];
                end
            end
            switch shape
                case 'polygon', h=drawpolygon(app.Axes,args{:});
                case 'freehand', h=drawfreehand(app.Axes,args{:});
                case 'rectangle', h=drawrectangle(app.Axes,args{:});
                case 'ellipse', h=drawellipse(app.Axes,args{:});
                otherwise, error('MPI:ROI','Unsupported ROI shape.');
            end
            if ~isvalid(h), h=[]; return; end
            if (isprop(h,'Position') && isempty(h.Position)) || ...
                    (strcmp(shape,'ellipse') && isempty(h.Center))
                delete(h);
                h=[];
                return;
            end
            % Set after drawing so interactive placement remains available.
            % Also applies to pasted, restored and loaded ROIs.
            app.setRoiInteraction(h,'translate');
            h.FaceSelectable=true;
            listeners=[addlistener(h,'ROIMoved',@(roi,~)app.roiMoved(roi)), ...
                addlistener(h,'MovingROI',@(roi,~)app.roiMoving(roi))];
            app.ROIs(end+1)=struct('Name',char(name),'Shape',shape,'Handle',h,'Listeners',listeners);
            app.Dirty=true;
            if ~deferRefresh
                app.refresh();
                set(app.RoiList,'Value',numel(app.ROIs));
            end
        end
        function setRoiInteraction(app,h,mode)
            h.InteractionsAllowed=mode;
            if isprop(h,'MarkersVisible')
                if strcmp(mode,'all')
                    h.MarkersVisible='on';
                else
                    h.MarkersVisible='off';
                end
            end
            app.setRoiEmphasis(h,false);
        end
        function setRoiEmphasis(~,h,adjusting)
            if ~isprop(h,'EdgeAlpha'), return; end
            alpha=.40;
            if adjusting, alpha=1; end
            if h.EdgeAlpha~=alpha, h.EdgeAlpha=alpha; end
        end
        function roiMoving(app,h)
            app.setRoiEmphasis(h,true);
            app.previewTimecourse(h);
        end
        function roiMoved(app,h)
            app.setRoiEmphasis(h,false);
            app.changed();
        end
        function changed(app)
            app.Dirty=true; app.refresh();
        end
        function setROIMode(app,mode)
            if isempty(app.ROIs)
                set(app.Status,'String','请先绘制或载入 ROI。'); return;
            end
            k=get(app.RoiList,'Value');
            app.leaveNavigation();
            % At most one outline is editable; all others remain move-only.
            for j=1:numel(app.ROIs)
                app.setRoiInteraction(app.ROIs(j).Handle,'translate');
            end
            app.setRoiInteraction(app.ROIs(k).Handle,mode);
            app.refresh();
            if strcmp(mode,'translate')
                set(app.Status,'String','仅移动模式：拖动 ROI 内部或边界可整体平移，形状和大小保持不变。');
            else
                set(app.Status,'String',sprintf('正在编辑「%s」：可修改轮廓，完成后点击“仅移动”。',app.ROIs(k).Name));
            end
        end
        function copyROI(app)
            if isempty(app.ROIs)
                set(app.Status,'String','请先勾画 ROI，并在右侧列表中选中要复制的区域。');
                return;
            end
            k=get(app.RoiList,'Value'); defs=app.definitions();
            % Store a value snapshot, never the live handle or source statistics.
            mask=createMask(app.ROIs(k).Handle,app.ImageHandle);
            app.ROIClipboard=struct('Definition',defs(k),'Source',app.File, ...
                'ImageSize',size(app.Data),'PixelSpacing',app.Meta.PixelSpacing, ...
                'Pixels',nnz(mask));
            set(app.Status,'String',sprintf('已复制 ROI「%s」。切换图像后点击“粘贴 ROI”。',defs(k).Name));
        end
        function pasteROI(app)
            if isempty(app.ROIClipboard)
                set(app.Status,'String','请先在源图像中选择 ROI 并点击“复制 ROI”。');
                return;
            end
            if isempty(app.Data)
                set(app.Status,'String','请先打开目标图像。');
                return;
            end
            clip=app.ROIClipboard; def=clip.Definition;
            physicalTransfer=all(isfinite(clip.PixelSpacing)) && all(clip.PixelSpacing>0) && ...
                all(isfinite(app.Meta.PixelSpacing)) && all(app.Meta.PixelSpacing>0);
            if physicalTransfer
                def=mpi_transform_roi_physical(def,clip.ImageSize,clip.PixelSpacing, ...
                    size(app.Data),app.Meta.PixelSpacing);
            end
            name=def.Name; suffix=1;
            while any(strcmp({app.ROIs.Name},name))
                name=sprintf('%s_副本%d',def.Name,suffix); suffix=suffix+1;
            end
            app.leaveNavigation();
            % addROI makes an independent editable ROI and recalculates on current Data.
            % The target background selection is intentionally unchanged.
            h=app.addROI(def.Shape,def.Position,name);
            mask=createMask(h,app.ImageHandle);
            msg=sprintf('已粘贴「%s」，按目标图像重新统计；可拖动调整位置。',name);
            if physicalTransfer
                sourceArea=clip.Pixels*prod(clip.PixelSpacing);
                targetArea=nnz(mask)*prod(app.Meta.PixelSpacing);
                msg=[msg sprintf(' 已按物理尺寸换算，面积 %.4g → %.4g mm²。',sourceArea,targetArea)];
                if abs(targetArea-sourceArea)>max(2*prod(app.Meta.PixelSpacing),.05*sourceArea)
                    msg=[msg ' 像素离散或超出图像使面积偏差较大，请检查。'];
                end
            else
                msg=[msg ' 缺少有效像素间距，仅按原像素坐标粘贴，无法保证实际面积相同。'];
            end
            if ~any(mask(:))
                msg=[msg ' 当前 ROI 未覆盖图内像素，请移动到图像内。'];
            elseif ~physicalTransfer && nnz(mask)~=clip.Pixels
                msg=[msg ' 图内像素数与源 ROI 不同，请检查是否超出图像边界。'];
            end
            if app.Background>0
                bg=createMask(app.ROIs(app.Background).Handle,app.ImageHandle);
                if any(mask(:) & bg(:))
                    msg=[msg ' 与目标背景重叠：暂不计算背景校正值。'];
                end
            end
            set(app.Status,'String',msg);
        end
        function copyAllROIs(app)
            if isempty(app.ROIs)
                set(app.Status,'String','当前图像没有可复制的 ROI。'); return;
            end
            pixels=zeros(1,numel(app.ROIs));
            for k=1:numel(app.ROIs)
                pixels(k)=nnz(createMask(app.ROIs(k).Handle,app.ImageHandle));
            end
            app.ROIBatchClipboard=struct('Definitions',app.definitions(), ...
                'Background',app.Background,'Source',app.File,'ImageSize',size(app.Data), ...
                'PixelSpacing',app.Meta.PixelSpacing,'Pixels',pixels);
            set(app.Status,'String',sprintf('已复制全部 %d 个 ROI（含已设定的背景），切换图像后点击“粘贴全部”。',numel(app.ROIs)));
        end
        function pasteAllROIs(app)
            if isempty(app.ROIBatchClipboard)
                set(app.Status,'String','请先在源图像点击“复制全部”。'); return;
            end
            if isempty(app.Data)
                set(app.Status,'String','请先打开目标图像。'); return;
            end
            clip=app.ROIBatchClipboard;
            physicalTransfer=all(isfinite(clip.PixelSpacing)) && all(clip.PixelSpacing>0) && ...
                all(isfinite(app.Meta.PixelSpacing)) && all(app.Meta.PixelSpacing>0);
            oldCount=numel(app.ROIs); oldBackground=app.Background; oldDirty=app.Dirty;
            oldSelection=get(app.RoiList,'Value');
            renamed=0; changedPixels=0; changedArea=0; emptyMasks=0; skippedBackground=false;
            app.leaveNavigation();
            try
                for k=1:numel(clip.Definitions)
                    % Keep an existing target background; do not paste a second
                    % background as an ordinary target ROI used by time curves.
                    if k==clip.Background && oldBackground>0
                        skippedBackground=true; continue;
                    end
                    def=clip.Definitions(k); name=def.Name; suffix=1;
                    if physicalTransfer
                        def=mpi_transform_roi_physical(def,clip.ImageSize,clip.PixelSpacing, ...
                            size(app.Data),app.Meta.PixelSpacing);
                    end
                    while any(strcmp({app.ROIs.Name},name))
                        name=sprintf('%s_副本%d',def.Name,suffix); suffix=suffix+1;
                    end
                    renamed=renamed+~strcmp(name,def.Name);
                    h=app.addROI(def.Shape,def.Position,name,true);
                    mask=createMask(h,app.ImageHandle);
                    if physicalTransfer
                        sourceArea=clip.Pixels(k)*prod(clip.PixelSpacing);
                        targetArea=nnz(mask)*prod(app.Meta.PixelSpacing);
                        changedArea=changedArea+(abs(targetArea-sourceArea)> ...
                            max(2*prod(app.Meta.PixelSpacing),.05*sourceArea));
                    else
                        changedPixels=changedPixels+(nnz(mask)~=clip.Pixels(k));
                    end
                    emptyMasks=emptyMasks+~any(mask(:));
                    if k==clip.Background, app.Background=numel(app.ROIs); end
                end
            catch ex
                % Roll back this batch without removing pre-existing target ROIs.
                for k=numel(app.ROIs):-1:oldCount+1
                    delete(app.ROIs(k).Listeners);
                    if isvalid(app.ROIs(k).Handle), delete(app.ROIs(k).Handle); end
                end
                app.ROIs=app.ROIs(1:oldCount); app.Background=oldBackground; app.Dirty=oldDirty;
                set(app.RoiList,'Value',oldSelection); app.refresh();
                rethrow(ex);
            end
            app.refresh();
            if numel(app.ROIs)>oldCount, set(app.RoiList,'Value',numel(app.ROIs)); end
            msg=sprintf('已粘贴 %d 个 ROI，默认仅移动；统计使用目标图像重新计算。',numel(app.ROIs)-oldCount);
            if skippedBackground
                msg=[msg ' 保留目标图已有背景，未重复粘贴源背景。'];
            elseif clip.Background>0
                msg=[msg ' 已一并设置粘贴的背景 ROI，请核对位置。'];
            end
            if renamed>0
                msg=[msg sprintf(' %d 个同名 ROI 已加副本后缀，时间曲线分析前请核对名称。',renamed)];
            end
            if physicalTransfer
                msg=[msg ' 已按实际 mm 尺寸换算到目标图像，以两图中心对齐；请检查解剖位置。'];
            else
                msg=[msg ' 缺少有效像素间距，仅按原像素坐标粘贴，无法保证实际面积相同。'];
            end
            if changedArea>0 || changedPixels>0 || emptyMasks>0
                msg=[msg sprintf(' %d 个 ROI 面积偏差较大，%d 个像素数改变，%d 个未覆盖图像，请检查边界。', ...
                    changedArea,changedPixels,emptyMasks)];
            end
            T=app.statistics();
            if ~isempty(T) && any(T.BackgroundOverlap>0)
                msg=[msg ' 有目标 ROI 与背景重叠，其背景校正值暂不计算。'];
            end
            set(app.Status,'String',msg);
        end
        function renameROI(app)
            if isempty(app.ROIs), return; end
            k=get(app.RoiList,'Value'); a=inputdlg('ROI 名称：','重命名',1,{app.ROIs(k).Name});
            if isempty(a) || isempty(strtrim(a{1})), return; end
            app.ROIs(k).Name=strtrim(a{1});
            app.ROIs(k).Handle.Color=app.roiColor(app.ROIs(k).Name);
            app.changed();
        end
        function removeROI(app)
            if isempty(app.ROIs), return; end
            k=get(app.RoiList,'Value'); delete(app.ROIs(k).Listeners); delete(app.ROIs(k).Handle); app.ROIs(k)=[];
            if app.Background==k, app.Background=0;
            elseif app.Background>k, app.Background=app.Background-1; end
            app.changed();
        end
        function setBackground(app)
            if isempty(app.ROIs), return; end
            app.Background=get(app.RoiList,'Value'); app.changed();
        end
        function clearBackground(app)
            app.Background=0; app.changed();
        end
        function [T,masks]=statistics(app)
            masks=cell(1,numel(app.ROIs)); T=table(); bg=[];
            for k=1:numel(app.ROIs), masks{k}=createMask(app.ROIs(k).Handle,app.ImageHandle); end
            if app.Background>0, bg=masks{app.Background}; end
            for k=1:numel(app.ROIs)
                usebg=bg; if k==app.Background, usebg=[]; end
                s=app.calculateRoiStats(masks{k},usebg);
                row=table(string(app.File),k,string(app.ROIs(k).Name),k==app.Background, ...
                    'VariableNames',{'Source','ROI_ID','ROI','IsBackground'});
                T=[T;[row struct2table(s)]]; %#ok<AGROW>
            end
        end
        function s=calculateRoiStats(app,mask,background)
            s=mpi_roi_stats(app.Data,mask,app.Meta.PixelSpacing,background, ...
                app.ThresholdMode,app.ThresholdK,app.FixedThreshold);
        end
        function refresh(app)
            names=cell(1,numel(app.ROIs));
            for k=1:numel(app.ROIs)
                names{k}=sprintf('%d: %s',k,app.ROIs(k).Name);
                if k==app.Background, names{k}=[names{k} ' [背景]']; end
                if strcmp(app.ROIs(k).Handle.InteractionsAllowed,'translate')
                    names{k}=[names{k} ' [仅移动]'];
                else
                    names{k}=[names{k} ' [编辑轮廓]'];
                end
                app.ROIs(k).Handle.Label='';
            end
            set(app.RoiList,'Value',max(1,min(get(app.RoiList,'Value'),numel(names))),'String',names);
            [T,masks]=app.statistics();
            app.CurrentStatistics=T;
            app.CurrentMasks=masks;
            app.refreshTimecourse(T);
            if isempty(T), set(app.ResultTable,'Data',{}); return; end
            cols={'ROI','Mean','BackgroundMean','CorrectedMean','CorrectedSum', ...
                'BackgroundSD','Pixels','ValidPixels', ...
                'Area_mm2','Sum','SD','Min','Max','Median','SNR','BackgroundOverlap', ...
                'Threshold','SignalPixels','SignalAreaPct','SignalMean','SignalSum','CorrectedSignalSum'};
            cells=table2cell(T(:,cols)); cells(:,1)=cellstr(T.ROI);
            set(app.ResultTable,'Data',cells,'ColumnName',cols,'ColumnEditable',false);
            if any(T.BackgroundOverlap>0)
                set(app.Status,'String','有目标 ROI 与背景重叠：该 ROI 的背景校正值和 SNR 暂不计算。');
            else
                set(app.Status,'String','统计基于还原后的有限数值，包含零和负值；显示范围不影响结果。');
            end
        end
        function color=roiColor(app,name,colors)
            if nargin<3, colors=app.ROIColors; end
            if ~isKey(colors,name)
                palette=lines(7);
                index=double(colors.Count)+1;
                if index<=size(palette,1)
                    colors(name)=palette(index,:);
                else
                    hue=mod((index-8)*0.61803398875,1);
                    colors(name)=hsv2rgb([hue .72 .70]);
                end
            end
            color=colors(name);
        end
        function prepareTimecourse(app)
            [~,~,app.ActiveTimeSeries]=app.cachedTimepoint(app.File);
            known=keys(app.TimepointCache);
            saved=keys(app.Cache);
            candidates=unique([app.Files(:);known(:);saved(:);{app.File}],'stable');
            ids=strings(size(candidates));
            animals=ids;
            minutes=nan(size(candidates));
            for k=1:numel(candidates)
                [animal,minute,key]=app.cachedTimepoint(candidates{k});
                ids(k)=key;
                animals(k)=animal;
                minutes(k)=minute;
            end
            available=string(app.ActiveTimeSeries);
            for k=1:numel(saved)
                cached=app.Cache(saved{k});
                if isfield(cached,'Statistics') && ~isempty(cached.Statistics)
                    [~,~,key]=app.cachedTimepoint(saved{k});
                    available(end+1,1)=string(key); %#ok<AGROW>
                end
            end
            series=struct('Key',{},'Animal',{},'Label',{},'Files',{},'Minutes',{});
            for key=reshape(unique(available(strlength(available)>0)),1,[])
                matches=ids==key & isfinite(minutes);
                files=candidates(matches);
                idsAtKey=animals(matches);
                if isempty(files), continue; end
                animal=idsAtKey(1);
                series(end+1)=struct('Key',key,'Animal',animal,'Label',animal, ...
                    'Files',{files},'Minutes',minutes(matches)); %#ok<AGROW>
            end
            names=[series.Animal];
            for k=1:numel(series)
                same=find(names==series(k).Animal);
                if numel(same)>1
                    series(k).Label=compose('%s [%d]',series(k).Animal,find(same==k,1));
                end
            end
            app.TimeSeries=series;
        end
        function [animal,time,key]=cachedTimepoint(app,file)
            if ~isKey(app.TimepointCache,file)
                [animal,time,key]=app.identifyTimepoint(file);
                app.TimepointCache(file)={animal,time,key};
            else
                point=app.TimepointCache(file);
                [animal,time,key]=point{:};
            end
        end
        function [animal,time,key]=identifyTimepoint(app,file)
            [folder,filename,extension]=fileparts(file);
            named=regexpi(filename,'^(C\d+-[A-Z]*\d+)(?:[-_ .]|$)','tokens','once');
            animal=''; key=''; time=app.minutesFromName(filename);
            if ~isempty(named), animal=upper(named{1}); end
            if contains(lower(filename),'tangential')
                projection='tangential';
            elseif contains(lower(filename),'combined')
                projection='combined';
            else
                projection='';
            end
            seriesFolder=folder; level=folder; legacy=''; legacyFolder='';
            while ~isempty(level)
                [parent,part,extensionPart]=fileparts(level);
                if strcmp(parent,level), break; end
                part=[part extensionPart];
                if isempty(projection) && (contains(lower(part),'tangential') || contains(part,'切向'))
                    projection='tangential';
                end
                fullID=regexpi(part,'^C\d+-[A-Z]*\d+$','once');
                shortID=regexpi(part,'^(?:M|RAT|MOUSE)\d+$','once');
                if ~isempty(fullID) || (~isempty(shortID) && isempty(animal))
                    if ~isempty(animal) && ~strcmpi(animal,part)
                        time=NaN; return;
                    end
                    animal=upper(part); seriesFolder=level;
                    break;
                end
                minute=app.minutesFromName(part);
                if isfinite(minute)
                    if isfinite(time) && time~=minute
                        time=NaN; return;
                    end
                    time=minute;
                    if isempty(legacy)
                        token=regexpi(part,'^((?:M|RAT|MOUSE)\d+)[-_ ]+\d','tokens','once');
                        if ~isempty(token), legacy=upper(token{1}); legacyFolder=parent; end
                    end
                end
                level=parent;
            end
            if isempty(animal) && ~isempty(legacy)
                animal=legacy; seriesFolder=legacyFolder;
            end
            if isempty(animal) || ~isfinite(time), return; end
            if strcmpi(extension,'.tiff'), extension='.tif'; end
            key=strjoin({lower(seriesFolder),animal,projection,lower(extension)},'|');
        end
        function time=minutesFromName(~,name)
            units=regexpi(name,'(?<![0-9.])(\d+(?:\.\d+)?)\s*(min|分钟|h|小时)(?![A-Z0-9])','tokens');
            time=NaN;
            if numel(units)~=1, return; end
            time=str2double(units{1}{1});
            if any(strcmpi(units{1}{2},{'h','小时'})), time=time*60; end
        end
        function previewTimecourse(app,h)
            if app.IsDrawingROI || isempty(app.ActiveTimeSeries) || isempty(app.CurrentStatistics), return; end
            if ~isempty(app.LastDragUpdate) && toc(app.LastDragUpdate)<.15, return; end
            k=find(arrayfun(@(roi)isequal(roi.Handle,h),app.ROIs),1);
            if isempty(k), return; end
            masks=app.CurrentMasks;
            masks{k}=createMask(h,app.ImageHandle);
            background=[];
            if app.Background>0, background=masks{app.Background}; end
            rows=k;
            if k==app.Background
                rows=1:numel(masks);
                rows(k)=[];
            end
            T=app.CurrentStatistics;
            for j=rows
                s=app.calculateRoiStats(masks{j},background);
                T.Sum(j)=s.Sum;
                T.CorrectedSum(j)=s.CorrectedSum;
                T.CorrectedMean(j)=s.CorrectedMean;
            end
            app.refreshTimecourse(T);
            app.LastDragUpdate=tic;
        end
        function layoutTimeRoiTable(app)
            if ~isgraphics(app.TimeRoiTable), return; end
            bounds=getpixelposition(app.TimeRoiTable);
            app.TimeRoiTable.ColumnWidth={44,max(70,floor(bounds(3))-62)};
        end
        function setTimeRoiShown(app,event)
            key=app.TimeCurveKeys(event.Indices(1));
            if event.NewData
                app.HiddenTimeRois(app.HiddenTimeRois==key)=[];
            else
                app.HiddenTimeRois=union(app.HiddenTimeRois,key);
            end
            app.refreshTimecourse(app.CurrentStatistics);
        end
        function updateTimeRoiTable(app,keys,labels,shown)
            cells=cell(numel(keys),2);
            cells(:,1)=num2cell(shown);
            for k=1:numel(keys)
                name=char(labels(k));
                color=sprintf('#%02X%02X%02X',round(255*app.roiColor(char(keys(k)),app.TimeColors)));
                name=strrep(strrep(strrep(name,'&','&amp;'),'<','&lt;'),'>','&gt;');
                cells{k,2}=sprintf('<html><font color="%s">&#9632;</font>&nbsp;%s</html>',color,name);
            end
            app.TimeRoiTable.Data=cells;
        end
        function [times,values,names,duplicateTimes,duplicateNames]=timeSeriesValues(app,series,current,column)
            [times,~,indices]=unique(series.Minutes);
            counts=accumarray(indices,ones(size(indices)));
            tables=cell(numel(times),1);
            names=strings(0,1);
            for k=1:numel(series.Files)
                if counts(indices(k))~=1, continue; end
                file=series.Files{k};
                if strcmp(app.File,file)
                    stats=current;
                elseif isKey(app.Cache,file)
                    cached=app.Cache(file);
                    if ~isfield(cached,'Statistics'), continue; end
                    stats=cached.Statistics;
                else
                    continue;
                end
                if isempty(stats), continue; end
                stats=stats(~stats.IsBackground,:);
                tables{indices(k)}=stats;
                names=union(names,stats.ROI,'stable');
            end
            values=nan(numel(times),numel(names));
            duplicateTimes=any(counts>1);
            duplicateNames=false;
            for k=1:numel(tables)
                stats=tables{k};
                if isempty(stats), continue; end
                [~,rows]=ismember(stats.ROI,names);
                repetitions=accumarray(rows,ones(height(stats),1),[numel(names) 1]);
                valid=repetitions(rows)==1;
                values(k,rows(valid))=stats.(column)(valid);
                duplicateNames=duplicateNames || any(repetitions>1);
            end
        end
        function refreshTimecourse(app,current)
            columns={'CorrectedSum','CorrectedMean','Sum'};
            titles={'校正后总信号','校正后平均信号','原始总信号'};
            metric=get(app.TimeMetric,'Value');
            keys=strings(0,1);
            labels=keys;
            animals=keys;
            x=cell(0,1);
            y=x;
            duplicateTimes=false;
            duplicateNames=false;
            for series=app.TimeSeries
                [times,values,names,timeConflict,nameConflict]=app.timeSeriesValues(series,current,columns{metric});
                duplicateTimes=duplicateTimes || timeConflict;
                duplicateNames=duplicateNames || nameConflict;
                if isempty(names), continue; end
                keys=[keys;series.Key+"|"+names]; %#ok<AGROW>
                labels=[labels;series.Label+" · "+names]; %#ok<AGROW>
                animals=[animals;repmat(series.Animal,numel(names),1)]; %#ok<AGROW>
                x=[x;repmat({times},numel(names),1)]; %#ok<AGROW>
                y=[y;num2cell(values,1).']; %#ok<AGROW>
            end
            shown=~ismember(keys,app.HiddenTimeRois);
            hasValues=cellfun(@(v)any(isfinite(v)),y);
            namesChanged=~isequal(keys,app.TimeCurveKeys) || ~isequal(labels,app.TimeNames);
            if namesChanged
                app.TimeCurveKeys=keys;
                app.TimeNames=labels;
                app.updateTimeRoiTable(keys,labels,shown);
            end
            ax=app.TimeAxes;
            if namesChanged || any(~isgraphics(app.TimeLines))
                cla(ax); hold(ax,'on');
                app.TimeLines=gobjects(numel(keys),1);
                for j=1:numel(keys)
                    app.TimeLines(j)=plot(ax,x{j},y{j},'-o','LineWidth',1.4, ...
                        'MarkerSize',4,'Color',app.roiColor(char(keys(j)),app.TimeColors), ...
                        'DisplayName',char(labels(j)),'HitTest','off');
                end
                hold(ax,'off');
            end
            for j=1:numel(keys)
                if ~shown(j), y{j}(:)=NaN; end
                set(app.TimeLines(j),'XData',x{j},'YData',y{j});
            end
            grid(ax,'on'); xlabel(ax,'注射后时间 (min)'); ylabel(ax,titles{metric});
            timeRange=vertcat(x{shown});
            if isempty(timeRange), timeRange=vertcat(app.TimeSeries.Minutes); end
            if isempty(timeRange)
                xlim(ax,'auto');
            else
                first=min(timeRange); last=max(timeRange);
                pad=max(1,.04*(last-first));
                xlim(ax,[first-pad,last+pad]);
            end
            if isempty(keys) && isempty(app.TimeSeries)
                msg='打开可识别动物编号和时间点的图像，勾画 ROI 后显示曲线。';
            else
                msg=sprintf('已选 %d/%d 条 · %d 只动物有信号', ...
                    nnz(shown),numel(keys),numel(unique(animals(shown & hasValues))));
                if ~isempty(keys) && ~any(shown)
                    msg=[msg '；请勾选要显示的 ROI'];
                elseif any(shown) && ~any(shown & hasValues) && metric~=3
                    msg=[msg '；请检查各图的背景 ROI'];
                end
                if duplicateTimes, msg=[msg '；已跳过同序列重复时间点']; end
                if duplicateNames, msg=[msg '；同图同名 ROI 未连线']; end
            end
            set(app.TimeStatus,'String',msg,'TooltipString',msg);
        end
        function defs=definitions(app)
            defs=struct('Name',{},'Shape',{},'Position',{});
            for k=1:numel(app.ROIs)
                h=app.ROIs(k).Handle;
                if strcmp(app.ROIs(k).Shape,'ellipse')
                    pos=struct('Center',h.Center,'SemiAxes',h.SemiAxes,'RotationAngle',h.RotationAngle);
                elseif strcmp(app.ROIs(k).Shape,'rectangle')
                    pos=struct('Position',h.Position,'RotationAngle',h.RotationAngle);
                else, pos=h.Position; end
                defs(end+1)=struct('Name',app.ROIs(k).Name,'Shape',app.ROIs(k).Shape,'Position',pos); %#ok<AGROW>
            end
        end
        function stash(app)
            if isempty(app.File), return; end
            app.Cache(app.File)=struct('Definitions',app.definitions(),'Background',app.Background, ...
                'Data',app.Data,'Dirty',app.Dirty,'Statistics',app.CurrentStatistics);
        end
        function clearGraphics(app)
            for k=1:numel(app.ROIs)
                delete(app.ROIs(k).Listeners);
                if isvalid(app.ROIs(k).Handle), delete(app.ROIs(k).Handle); end
            end
            app.ROIs=struct('Name',{},'Shape',{},'Handle',{},'Listeners',{});
        end
        function restore(app,defs,bg)
            for k=1:numel(defs)
                app.addROI(defs(k).Shape,defs(k).Position,defs(k).Name,true);
            end
            app.Background=bg; app.refresh();
            if ~isempty(app.ROIs), set(app.RoiList,'Value',numel(app.ROIs)); end
        end
        function session=makeSession(app)
            [T,masks]=app.statistics();
            session=struct('Version',1,'Source',app.File,'Metadata',app.Meta,'Data',app.Data, ...
                'Definitions',app.definitions(),'Background',app.Background,'Masks',{masks}, ...
                'Statistics',T,'CLim',get(app.Axes,'CLim'),'Created',char(datetime('now')), ...
                'ThresholdMode',app.ThresholdMode,'ThresholdK',app.ThresholdK, ...
                'FixedThreshold',app.FixedThreshold);
        end
        function saveROIs(app)
            if isempty(app.Data), return; end
            [f,p]=uiputfile('*.mat','保存当前图像 ROI',fullfile(fileparts(mfilename('fullpath')),'roi_session.mat'));
            if isequal(f,0), return; end
            session=app.makeSession(); save(fullfile(p,f),'session','-v7');
            app.Dirty=false; set(app.Status,'String',['已保存: ' fullfile(p,f)]);
        end
        function loadROIs(app)
            if isempty(app.Data), return; end
            [f,p]=uigetfile('*.mat','载入当前图像的 ROI 会话');
            if isequal(f,0), return; end
            x=load(fullfile(p,f),'session');
            if ~isfield(x,'session') || ~isfield(x.session,'Version') || x.session.Version~=1
                error('MPI:Session','不是本工具支持的 ROI 会话。');
            end
            s=x.session;
            if ~strcmpi(s.Source,app.File) || ~isequaln(s.Data,app.Data)
                error('MPI:Mismatch','会话来源或图像数值不同。请打开保存该 ROI 时的原图。');
            end
            if ~isempty(app.ROIs)
                a=questdlg('载入会替换当前图像的 ROI，是否继续？','载入 ROI','替换','取消','取消');
                if ~strcmp(a,'替换'), return; end
            end
            app.clearGraphics(); app.Background=0;
            if isfield(s,'ThresholdMode')
                app.ThresholdMode=s.ThresholdMode;
                app.ThresholdK=s.ThresholdK;
                app.FixedThreshold=s.FixedThreshold;
                set(app.KEdit,'String',num2str(app.ThresholdK));
                set(app.FixedEdit,'String',num2str(app.FixedThreshold));
                set(findobj(app.Figure,'Tag','threshold_background'),'Value',strcmp(app.ThresholdMode,'background'));
                set(findobj(app.Figure,'Tag','threshold_fixed'),'Value',strcmp(app.ThresholdMode,'fixed'));
            end
            app.restore(s.Definitions,s.Background);
            app.Dirty=false; app.stash();
        end
        function out=exportResults(app,parent)
            out=''; if isempty(app.ROIs), return; end
            if nargin<2
                default=fullfile(fileparts(mfilename('fullpath')),'results');
                if ~isfolder(default), mkdir(default); end
                parent=uigetdir(default,'选择结果保存目录');
                if isequal(parent,0), return; end
            end
            suggested=['ROI_' char(datetime('now','Format','yyyyMMdd_HHmmss'))];
            while true
                answer=inputdlg('结果文件夹名称（支持中文，例如 m5_170min）：', ...
                    '命名导出文件夹',1,{suggested});
                if isempty(answer), return; end
                name=strtrim(answer{1});
                if isempty(name) || all(name=='.') || ...
                        ~isempty(regexp(name,'[<>:"/\\|?*\x00-\x1F]','once')) || ...
                        endsWith(name,'.') || ...
                        ~isempty(regexpi(name,'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)','once'))
                    uiwait(errordlg('请输入有效文件夹名称，不能包含路径分隔符或 Windows 禁用字符。','文件夹名称无效','modal'));
                    suggested=name; continue;
                end
                candidate=fullfile(parent,name);
                if isfolder(candidate) || isfile(candidate)
                    uiwait(errordlg('此名称已存在，请换一个名称；已有结果不会被覆盖。','名称已存在','modal'));
                    suggested=[name '_新']; continue;
                end
                [ok,msg,msgid]=mkdir(candidate);
                if ~ok || ~isempty(msgid)
                    error('MPI:ExportFolder','无法新建结果文件夹：%s',msg);
                end
                out=candidate; break;
            end
            session=app.makeSession();
            T=session.Statistics;
            T.RescaleSlope=repmat(app.Meta.Slope,height(T),1);
            T.RescaleIntercept=repmat(app.Meta.Intercept,height(T),1);
            T.RowSpacing_mm=repmat(app.Meta.PixelSpacing(1),height(T),1);
            T.ColumnSpacing_mm=repmat(app.Meta.PixelSpacing(2),height(T),1);
            T.Units=repmat(string(app.Meta.Units),height(T),1);
            mpi_write_results(T,out);
            [thresholdTable,signalMask]=mpi_threshold_results(app.Data,session.Masks, ...
                session.Definitions,app.Background,app.Meta.PixelSpacing, ...
                app.ThresholdMode,app.ThresholdK,app.FixedThreshold,app.File);
            if ~isempty(thresholdTable)
                csvFile=fullfile(out,'mpi_roi_quantification.csv');
                writetable(thresholdTable,csvFile,'Encoding','UTF-8');
                mpi_ensure_utf8_bom(csvFile);
                combinedTarget=false(size(app.Data));
                for j=1:numel(session.Masks)
                    if j~=app.Background, combinedTarget=combinedTarget | session.Masks{j}; end
                end
                imwrite(uint8(combinedTarget)*255,fullfile(out,'target_mask.png'));
                imwrite(uint8(session.Masks{app.Background})*255,fullfile(out,'background_mask.png'));
                imwrite(uint8(signalMask)*255,fullfile(out,'signal_mask.png'));
            end
            session.Statistics=T; save(fullfile(out,'roi_session.mat'),'session','-v7');
            exportgraphics(app.Axes,fullfile(out,'roi_overlay.png'),'Resolution',180);
            app.Dirty=false; app.stash();
            set(app.Status,'String',['已导出统计 Excel/XLSX 和 UTF-8 CSV、ROI 会话/掩膜 MAT、叠加 PNG: ' out]);
        end
        function out=exportAllResults(app)
            % Export one combined table for every annotated image in the file list.
            out='';
            if isempty(app.File), error('MPI:Batch','请先打开数据文件夹或图像。'); end
            app.stash();
            files=app.Files;
            if isempty(files), files={app.File}; end
            if ~any(strcmp(files,app.File)), files{end+1}=app.File; end
            template=app.definitions(); templateBackground=app.Background;
            templateSize=size(app.Data); templateSpacing=app.Meta.PixelSpacing;
            unannotated=0;
            for j=1:numel(files)
                if ~isKey(app.Cache,files{j}), unannotated=unannotated+1; continue; end
                cached=app.Cache(files{j});
                if isempty(cached.Definitions), unannotated=unannotated+1; end
            end
            applyTemplate=false;
            if unannotated>0 && ~isempty(template)
                answer=questdlg(sprintf(['%d 张图像尚未标注 ROI。是否把当前图像的 ROI 按实际毫米尺寸' ...
                    '套用到未标注图像？缺少像素间距且尺寸不同的图像会跳过。'],unannotated), ...
                    '批量导出 ROI 选择','套用当前 ROI','只导出已标注','取消','只导出已标注');
                if isempty(answer) || strcmp(answer,'取消'), return; end
                applyTemplate=strcmp(answer,'套用当前 ROI');
            end
            default=fullfile(fileparts(mfilename('fullpath')),'results');
            if ~isfolder(default), mkdir(default); end
            parent=uigetdir(default,'选择全部结果的保存目录');
            if isequal(parent,0), return; end
            suggested=['全部ROI_' char(datetime('now','Format','yyyyMMdd_HHmmss'))];
            while true
                answer=inputdlg('新结果文件夹名称（支持中文）：', ...
                    '命名批量导出文件夹',1,{suggested});
                if isempty(answer), return; end
                name=strtrim(answer{1});
                if isempty(name) || all(name=='.') || ...
                        ~isempty(regexp(name,'[<>:"/\\|?*\x00-\x1F]','once')) || ...
                        endsWith(name,'.') || ...
                        ~isempty(regexpi(name,'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)','once'))
                    uiwait(errordlg('请输入有效文件夹名称，不能包含路径分隔符或 Windows 禁用字符。', ...
                        '文件夹名称无效','modal'));
                    suggested=name; continue;
                end
                out=fullfile(parent,name);
                if isfolder(out) || isfile(out)
                    uiwait(errordlg('此名称已存在，请换一个名称；已有结果不会被覆盖。', ...
                        '名称已存在','modal'));
                    suggested=[name '_新']; continue;
                end
                break;
            end
            originalFile=app.File; originalLimits=get(app.Axes,'CLim');
            originalROISelection=get(app.RoiList,'Value');
            restoreGuard=onCleanup(@()app.restoreBatchView( ...
                originalFile,originalLimits,originalROISelection));
            allStats=table(); allThreshold=table();
            maskBundles=cell(numel(files),1);
            manifest=table(string(files(:)),strings(numel(files),1),strings(numel(files),1), ...
                false(numel(files),1),strings(numel(files),1),false(numel(files),1), ...
                'VariableNames', ...
                {'Source','Status','Reason','ThresholdExported','MaskFolder','MaskExported'});
            for j=1:numel(files)
                file=files{j};
                templated=false;
                try
                    hasROIs=false;
                    if isKey(app.Cache,file)
                        cached=app.Cache(file); hasROIs=~isempty(cached.Definitions);
                    end
                    if ~hasROIs
                        if ~applyTemplate
                            manifest.Status(j)="跳过"; manifest.Reason(j)="未标注 ROI"; continue;
                        end
                        [data,meta]=mpi_read_image(file);
                        newDefinitions=template;
                        if all(isfinite(templateSpacing)) && all(templateSpacing>0) && ...
                                all(isfinite(meta.PixelSpacing)) && all(meta.PixelSpacing>0)
                            for k=1:numel(template)
                                newDefinitions(k)=mpi_transform_roi_physical(template(k), ...
                                    templateSize,templateSpacing,size(data),meta.PixelSpacing);
                            end
                        elseif ~isequal(size(data),templateSize)
                            manifest.Status(j)="跳过";
                            manifest.Reason(j)="图像尺寸不同且缺少像素间距，无法换算 ROI";
                            continue;
                        else
                            manifest.Reason(j)="缺少像素间距，沿用像素坐标；实际面积未保证";
                        end
                        app.Cache(file)=struct('Definitions',newDefinitions,'Background',templateBackground, ...
                            'Data',data,'Dirty',true);
                        templated=true;
                    end
                    app.openImage(file);
                    if isempty(app.ROIs)
                        manifest.Status(j)="跳过"; manifest.Reason(j)="ROI 缓存与图像不匹配"; continue;
                    end
                    session=app.makeSession(); T=session.Statistics;
                    T.RescaleSlope=repmat(app.Meta.Slope,height(T),1);
                    T.RescaleIntercept=repmat(app.Meta.Intercept,height(T),1);
                    T.RowSpacing_mm=repmat(app.Meta.PixelSpacing(1),height(T),1);
                    T.ColumnSpacing_mm=repmat(app.Meta.PixelSpacing(2),height(T),1);
                    T.Units=repmat(string(app.Meta.Units),height(T),1);
                    [Q,signalMask]=mpi_threshold_results(app.Data,session.Masks, ...
                        session.Definitions,app.Background,app.Meta.PixelSpacing, ...
                        app.ThresholdMode,app.ThresholdK,app.FixedThreshold,app.File);
                    nextStats=[allStats;T]; %#ok<AGROW>
                    if ~isempty(Q)
                        Q.Source=repmat(string(app.File),height(Q),1);
                        nextThreshold=[allThreshold;Q]; %#ok<AGROW>
                        manifest.ThresholdExported(j)=true;
                    else
                        nextThreshold=allThreshold;
                        manifest.Reason(j)="缺少背景或目标 ROI，仅导出逐 ROI 统计";
                    end
                    allStats=nextStats; allThreshold=nextThreshold;
                    maskBundles{j}=struct('Masks',{session.Masks}, ...
                        'Definitions',session.Definitions,'Background',app.Background, ...
                        'Source',app.File,'SignalMask',signalMask, ...
                        'HasSignal',~isempty(Q));
                    manifest.Status(j)="导出";
                catch ex
                    manifest.Status(j)="失败"; manifest.Reason(j)=string(ex.message);
                    if templated && isKey(app.Cache,file) && ~strcmp(app.File,file)
                        remove(app.Cache,file);
                    end
                end
            end
            clear restoreGuard; % Return to the originally displayed image.
            if isempty(allStats)
                error('MPI:Batch','没有可导出的 ROI 统计。请标注图像或套用当前 ROI。');
            end
            if isfolder(out) || isfile(out)
                error('MPI:Batch','结果文件夹已存在，未覆盖：%s',out);
            end
            [ok,msg]=mkdir(out);
            if ~ok, error('MPI:Batch','无法创建结果文件夹：%s',msg); end
            mpi_write_results(allStats,out);
            if ~isempty(allThreshold)
                csvFile=fullfile(out,'mpi_roi_quantification.csv');
                writetable(allThreshold,csvFile,'Encoding','UTF-8');
                mpi_ensure_utf8_bom(csvFile);
            end
            masksRoot=fullfile(out,'masks');
            [ok,msg]=mkdir(masksRoot);
            if ~ok, error('MPI:Batch','无法创建掩膜文件夹：%s',msg); end
            for j=1:numel(files)
                if manifest.Status(j)~="导出", continue; end
                folderName=sprintf('%04d',j);
                maskFolder=fullfile(masksRoot,folderName);
                manifest.MaskFolder(j)=string(fullfile('masks',folderName));
                try
                    [ok,msg]=mkdir(maskFolder);
                    if ~ok, error('MPI:Batch','无法创建图像掩膜文件夹：%s',msg); end
                    bundle=maskBundles{j};
                    targetMask=false(size(bundle.Masks{1}));
                    for k=1:numel(bundle.Masks)
                        mask=bundle.Masks{k};
                        imwrite(uint8(mask)*255, ...
                            fullfile(maskFolder,sprintf('roi_%03d.png',k)));
                        if k~=bundle.Background, targetMask=targetMask | mask; end
                    end
                    imwrite(uint8(targetMask)*255,fullfile(maskFolder,'target_mask.png'));
                    if bundle.Background>0
                        imwrite(uint8(bundle.Masks{bundle.Background})*255, ...
                            fullfile(maskFolder,'background_mask.png'));
                    end
                    if bundle.HasSignal
                        imwrite(uint8(bundle.SignalMask)*255, ...
                            fullfile(maskFolder,'signal_mask.png'));
                    end
                    masks=bundle.Masks; definitions=bundle.Definitions;
                    background=bundle.Background; source=bundle.Source;
                    signalMask=bundle.SignalMask;
                    save(fullfile(maskFolder,'roi_masks.mat'), ...
                        'masks','definitions','background','source','signalMask','-v7');
                    manifest.MaskExported(j)=true;
                catch ex
                    manifest.Reason(j)=strtrim(manifest.Reason(j)+" 掩膜导出失败："+string(ex.message));
                end
            end
            writetable(manifest,fullfile(out,'batch_manifest.csv'),'Encoding','UTF-8');
            mpi_ensure_utf8_bom(fullfile(out,'batch_manifest.csv'));
            for j=1:numel(files)
                if manifest.Status(j)=="导出" && manifest.MaskExported(j) && isKey(app.Cache,files{j})
                    cached=app.Cache(files{j}); cached.Dirty=false;
                    app.Cache(files{j})=cached;
                end
            end
            if strcmp(app.File,originalFile) && isKey(app.Cache,originalFile)
                cached=app.Cache(originalFile); app.Dirty=cached.Dirty;
            end
            exported=sum(manifest.Status=="导出");
            masked=sum(manifest.MaskExported);
            set(app.Status,'String',sprintf('已导出 %d/%d 张图像的统计、%d 张图像的掩膜：%s', ...
                exported,numel(files),masked,out));
            msgbox(sprintf('已导出 %d/%d 张图像的统计、%d 张图像的掩膜。详情见 batch_manifest.csv。', ...
                exported,numel(files),masked),'批量导出完成');
        end
        function restoreBatchView(app,file,limits,roiSelection)
            if isempty(file), return; end
            try
                app.openImage(file);
                app.setDisplayLimits(limits);
                set(app.RoiList,'Value',max(1,min(roiSelection,numel(app.ROIs))));
            catch ex
                set(app.Status,'String',['批量导出后恢复原图失败: ' ex.message]);
            end
        end
        function closeApp(app)
            if app.IsDrawingROI
                set(app.Status,'String','正在勾画 ROI。完成后关闭，或按 Esc 取消。');
                return;
            end
            app.stash(); values=app.Cache.values; unsaved=false;
            for k=1:numel(values), unsaved=unsaved || values{k}.Dirty; end
            if unsaved
                a=questdlg('有尚未保存的 ROI 修改（可能位于其他图像）。关闭后将丢失。','关闭工具','关闭','返回保存','返回保存');
                if ~strcmp(a,'关闭'), return; end
            end
            delete(app.Figure);
        end
    end
end
