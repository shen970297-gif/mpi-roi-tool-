function [data,outDir] = plot_mpi_timecourses(dataDir)
%PLOT_MPI_TIMECOURSES Plot each ROI's CorrectedSum and CorrectedMean over time.
% [data,outDir] = plot_mpi_timecourses;
% [data,outDir] = plot_mpi_timecourses('C:\...\results\m5');
% Reads immediate timepoint folders such as 033_45min; XLSX preferred to CSV.
% Does not launch the ROI app, modify measurements, or recalculate ROI signals.
if nargin<1 || isempty(dataDir)
    dataDir=fullfile(fileparts(mfilename('fullpath')),'results','m5');
end
dataDir=char(dataDir);
if ~isfolder(dataDir), error('MPI:Folder','数据目录不存在：%s',dataDir); end
[~,animal]=fileparts(dataDir);
if isempty(animal), [~,animal]=fileparts(fileparts(dataDir)); end
folders=dir(dataDir); folders=folders([folders.isdir]);
data=table(); seenTimes=[];
required={'ROI','IsBackground','CorrectedSum','CorrectedMean','ValidPixels','Source'};
for k=1:numel(folders)
    folder=folders(k).name;
    if startsWith(folder,'.'), continue; end
    scanDir=fullfile(dataDir,folder);
    file=fullfile(scanDir,'roi_statistics.xlsx');
    isCSV=false;
    if ~isfile(file)
        file=fullfile(scanDir,'roi_statistics.csv'); isCSV=true;
    end
    if ~isfile(file), continue; end
    % Read the number next to a unit, never the acquisition index (e.g. 033).
    tokens=regexpi(folder,'(?:^|[_\s-])(\d+(?:\.\d+)?)\s*(min|分钟|h|小时)(?=$|[_\s-])','tokens');
    if numel(tokens)~=1
        error('MPI:Time','无法唯一识别时间：%s。请使用如 033_45min 的文件夹名称。',folder);
    end
    time=str2double(tokens{1}{1});
    if any(strcmpi(tokens{1}{2},{'h','小时'})), time=time*60; end
    if any(seenTimes==time)
        error('MPI:DuplicateTime','%g min 有多份导出，请保留一份或移开重复文件夹。',time);
    end
    seenTimes(end+1)=time; %#ok<AGROW>
    if isCSV
        T=readtable(file,'Encoding','UTF-8','TextType','string','VariableNamingRule','preserve');
    else
        T=readtable(file,'Sheet','ROI Statistics','TextType','string','VariableNamingRule','preserve');
    end
    if ~all(ismember(required,T.Properties.VariableNames))
        error('MPI:Columns','文件缺少必要列：%s',file);
    end
    names=strtrim(string(T.ROI));
    bg=str2double(string(T.IsBackground));
    % Support both numeric 0/1 and logical true/false representations.
    bg(strcmpi(string(T.IsBackground),'true'))=1;
    bg(strcmpi(string(T.IsBackground),'false'))=0;
    if any(~ismember(bg,[0 1]))
        error('MPI:Background','IsBackground 列必须是 0/1 或 true/false：%s',file);
    end
    keep=bg==0; T=T(keep,:); names=names(keep);
    if isempty(T)
        warning('MPI:ROI','文件仅含背景或没有目标 ROI，该时间点保留为缺失：%s',file);
        continue;
    end
    if any(ismissing(names) | strlength(names)==0) || numel(unique(names))~=numel(names)
        error('MPI:Names','区域名为空或重复，请核对：%s',file);
    end
    values=asNumbers(T.CorrectedSum,'CorrectedSum',file);
    means=asNumbers(T.CorrectedMean,'CorrectedMean',file);
    pixels=asNumbers(T.ValidPixels,'ValidPixels',file);
    if any(~isfinite(pixels) | pixels<0 | pixels~=fix(pixels))
        error('MPI:Pixels','有效像素数无效：%s',file);
    end
    sources=string(T.Source);
    rows=table(repmat(string(animal),height(T),1),repmat(time,height(T),1),names,values,means,pixels, ...
        sources,repmat(string(folder),height(T),1),repmat(string(file),height(T),1), ...
        'VariableNames',{'Animal','Time_min','ROI','CorrectedSum','CorrectedMean','ValidPixels','Source','ScanFolder','ResultFile'});
    data=[data;rows]; %#ok<AGROW>
end
if isempty(data), error('MPI:NoData','未找到可绘图的非背景 ROI，请检查时间点文件中的 IsBackground 列。'); end
data=sortrows(data,{'Time_min','ROI'});
times=sort(seenTimes(:));
if numel(times)<2, warning('MPI:OneTime','只有一个时间点，将显示单点。'); end
% Prevent mixing projection types such as combined and tangential.
sourceNames=strings(height(data),1);
for k=1:height(data)
    [~,base,ext]=fileparts(char(data.Source(k))); sourceNames(k)=string([base ext]);
end
if numel(unique(sourceNames))>1
    error('MPI:SourceType','源图像文件名不同，可能混入不同投影类型。请核对 Source 列后再绘图。');
end
% Union of all non-background ROI names; no predefined anatomy or count.
regions=unique(data.ROI,'stable');
nRegions=numel(regions);
nCols=min(3,ceil(sqrt(nRegions)));
nRows=ceil(nRegions/nCols);
signals=nan(numel(times),numel(regions)); meanSignals=signals; counts=signals;
for k=1:numel(regions)
    rows=data(data.ROI==regions(k),:);
    [~,indices]=ismember(rows.Time_min,times);
    signals(indices,k)=rows.CorrectedSum;
    meanSignals(indices,k)=rows.CorrectedMean;
    counts(indices,k)=rows.ValidPixels;
    p=rows.ValidPixels;
    if numel(unique(p))>1
        warning('MPI:ChangingROI','%s：有效像素数随时间变化（%g–%g）。总信号可能受 ROI 大小影响。',char(regions(k)),min(p),max(p));
    end
    if any(~isfinite(signals(:,k))) || any(~isfinite(meanSignals(:,k)))
        warning('MPI:Missing','%s 有缺失或不可用的校正信号，曲线将断开，不填零。',char(regions(k)));
    end
end
outRoot=fullfile(dataDir,'_time_curves');
if ~isfolder(outRoot), mkdir(outRoot); end
stamp=char(datetime('now','Format','yyyyMMdd_HHmmss'));
outDir=fullfile(outRoot,stamp); suffix=1;
while isfolder(outDir) || isfile(outDir)
    outDir=fullfile(outRoot,sprintf('%s_%d',stamp,suffix)); suffix=suffix+1;
end
[ok,msg]=mkdir(outDir); if ~ok, error('MPI:Output','%s',msg); end
summary=fullfile(outDir,'timecourse_summary.xlsx');
writetable(data,summary,'Sheet','All_ROI_Data','UseExcel',false);
% Use stable generic column IDs plus a mapping sheet to preserve arbitrary ROI names.
wide=table(times,'VariableNames',{'Time_min'}); meanTable=wide; pixelTable=wide;
regionIDs=compose('ROI_%02d',(1:numel(regions))');
for k=1:numel(regions)
    wide.(char(regionIDs(k)))=signals(:,k);
    meanTable.(char(regionIDs(k)))=meanSignals(:,k);
    pixelTable.(char(regionIDs(k)))=counts(:,k);
end
writetable(wide,summary,'Sheet','CorrectedSum','UseExcel',false);
writetable(meanTable,summary,'Sheet','CorrectedMean','UseExcel',false);
writetable(pixelTable,summary,'Sheet','ValidPixels','UseExcel',false);
writetable(table(regionIDs,regions,'VariableNames',{'Column','ROI'}),summary,'Sheet','ROI_Names','UseExcel',false);
colors=lines(numel(regions));
metricNames={'CorrectedSum','CorrectedMean'};
metricLabels={'背景校正总信号 (a.u.)','背景校正平均信号 (a.u.)'};
metricData={signals,meanSignals};
for metric=1:numel(metricNames)
metricDir=fullfile(outDir,metricNames{metric}); mkdir(metricDir);
currentSignals=metricData{metric};
for k=1:numel(regions)
    f=figure('Color','w','Name',[animal ' - ' char(regions(k)) ' - ' metricNames{metric}], ...
        'NumberTitle','off','Position',[160 130 850 580]);
    ax=axes('Parent',f);
    drawCurve(ax,times,currentSignals(:,k),colors(k,:),[animal ' · ' char(regions(k))],metricLabels{metric});
    filename=sprintf('%02d_%s',k,char(regions(k)));
    filename=regexprep(filename,'[<>:"/\\|?*\x00-\x1F]','_');
    exportgraphics(f,fullfile(metricDir,[filename '.png']),'Resolution',300);
    savefig(f,fullfile(metricDir,[filename '.fig']));
end
f=figure('Color','w','Name',[animal ' - 全部区域 - ' metricNames{metric}],'NumberTitle','off', ...
    'Position',[80 60 max(650,500*nCols) max(420,300*nRows)]);
layout=tiledlayout(f,nRows,nCols,'TileSpacing','compact','Padding','compact');
for k=1:numel(regions)
    ax=nexttile(layout);
    drawCurve(ax,times,currentSignals(:,k),colors(k,:),char(regions(k)),metricLabels{metric});
end
title(layout,[animal '：' metricLabels{metric}],'Interpreter','none');
exportgraphics(f,fullfile(metricDir,'all_regions.png'),'Resolution',300);
savefig(f,fullfile(metricDir,'all_regions.fig'));
end
fprintf('\n读取 %d 个时间点，%d 个区域。\n结果保存到：%s\n',numel(times),numel(regions),outDir);
disp(data(:,{'Time_min','ROI','CorrectedSum','CorrectedMean','ValidPixels'}));
end

function values=asNumbers(column,label,file)
raw=strtrim(string(column)); values=str2double(raw);
missing=ismissing(raw) | strlength(raw)==0 | strcmpi(raw,'NaN') | strcmpi(raw,'<missing>');
if any(isnan(values) & ~missing)
    error('MPI:Number','%s 存在无法识别的数值：%s',label,file);
end
values(~isfinite(values))=NaN;
end

function drawCurve(ax,times,values,color,plotTitle,yLabel)
plot(ax,times,values,'-o','Color',color,'LineWidth',1.7, ...
    'MarkerFaceColor',color,'MarkerSize',6);
hold(ax,'on');
yline(ax,0,':','Color',[.5 .5 .5],'HandleVisibility','off');
hold(ax,'off');
xlabel(ax,'时间 (min)'); ylabel(ax,yLabel);
title(ax,plotTitle,'Interpreter','none');
grid(ax,'on'); box(ax,'off');
set(ax,'FontName','Microsoft YaHei','FontSize',11,'LineWidth',1,'TickDir','out','GridAlpha',.15);
xticks(ax,times);
span=max(times)-min(times); padding=max(1,.05*span);
xlim(ax,[min(times)-padding,max(times)+padding]);
% No smoothing, normalization, physical-area multiplication, or error bars.
end
