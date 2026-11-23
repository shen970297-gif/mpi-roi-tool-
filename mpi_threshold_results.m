function [T,signalMask]=mpi_threshold_results(data,masks,defs,background,spacing,mode,k,fixed,source)
%MPI_THRESHOLD_RESULTS Export combined-target metrics on the native image grid.
% Legacy world2 columns now use mm^2 factors; spatial_unit identifies the scale.
T=table(); signalMask=false(size(data));
if background<1 || background>numel(masks), return; end
target=false(size(data));
for j=1:numel(masks)
    if j~=background, target=target | masks{j}; end
end
bg=masks{background};
if ~any(target & isfinite(data),'all') || ~any(bg & isfinite(data),'all'), return; end
s=mpi_roi_stats(data,target,spacing,bg,mode,k,fixed);
signalMask=target & isfinite(data) & data>=s.Threshold;
v=double(data(target & isfinite(data)));
b=double(data(bg & isfinite(data)));
sv=double(data(signalMask));
[rows,cols]=size(data);
dx=NaN; dy=NaN;
spatialUnit="unknown";
weightedX=NaN; weightedY=NaN;
if all(isfinite(spacing)) && all(spacing>0)
    dy=spacing(1); dx=spacing(2);
    spatialUnit="mm";
    weights=max(sv-s.BackgroundMean,0);
    totalWeight=sum(weights);
    if totalWeight>0
        [signalRows,signalCols]=find(signalMask);
        % Coordinates in mm relative to the image center; x right, y down.
        x=(signalCols-(cols+1)/2)*dx;
        y=(signalRows-(rows+1)/2)*dy;
        weightedX=sum(x.*weights)/totalWeight;
        weightedY=sum(y.*weights)/totalWeight;
    end
end
pixelArea=dx*dy;
signalMean=NaN; signalMax=NaN; correctedSignalMax=NaN;
if ~isempty(sv)
    signalMean=mean(sv); signalMax=max(sv);
    correctedSignalMax=signalMax-s.BackgroundMean;
end
sbr=NaN; cnr=NaN;
if isfinite(signalMean) && s.BackgroundMean~=0, sbr=signalMean/s.BackgroundMean; end
if isfinite(signalMean) && s.BackgroundSD>0
    cnr=(signalMean-s.BackgroundMean)/s.BackgroundSD;
end
[~,filename,ext]=fileparts(source);
time=NaN;
token=regexp([filename ext],'(?:^|[-_])(?:T)?(\d+)(?:min|[-_.]|$)','tokens','once','ignorecase');
if ~isempty(token), time=str2double(token{1}); end
targetDefs=defs; targetDefs(background)=[];
r=struct();
r.file=string([filename ext]); r.source_format=string(lower(erase(ext,'.'))); r.time=time;
r.threshold_mode=string(mode); r.threshold_k=k; r.fixed_threshold=fixed;
r.target_roi_count=numel(targetDefs); r.target_rois_json=string(jsonencode(targetDefs));
r.background_roi_type=string(defs(background).Shape);
r.background_roi_center_x=NaN; r.background_roi_center_y=NaN;
r.background_roi_radius_x=NaN; r.background_roi_radius_y=NaN;
r.background_roi_vertices_json="";
pos=defs(background).Position;
if strcmp(defs(background).Shape,'ellipse')
    r.background_roi_center_x=pos.Center(1); r.background_roi_center_y=pos.Center(2);
    r.background_roi_radius_x=pos.SemiAxes(1); r.background_roi_radius_y=pos.SemiAxes(2);
else
    if isstruct(pos), pos=pos.Position; end
    r.background_roi_vertices_json=string(jsonencode(pos));
end
r.rows=rows; r.cols=cols; r.sample_dx=dx; r.sample_dy=dy; r.sample_area=pixelArea;
r.target_area_px=numel(v); r.target_area_world2=numel(v)*pixelArea;
r.target_mean=mean(v); r.target_max=max(v); r.target_sum=sum(v);
r.target_integral_world2=r.target_sum*pixelArea;
r.background_area_px=numel(b); r.background_mean=s.BackgroundMean;
r.background_sd=0; if numel(b)>1, r.background_sd=s.BackgroundSD; end
r.background_median=median(b); r.threshold=s.Threshold;
r.signal_area_px=numel(sv); r.signal_area_world2=numel(sv)*pixelArea;
r.signal_area_pct=100*numel(sv)/numel(v);
r.signal_mean=signalMean; r.signal_max=signalMax; r.signal_sum=sum(sv);
r.signal_integral_world2=r.signal_sum*pixelArea;
r.corrected_target_mean=r.target_mean-r.background_mean;
r.corrected_target_sum=r.target_sum-r.background_mean*numel(v);
r.corrected_target_integral_world2=r.corrected_target_sum*pixelArea;
r.corrected_signal_max=correctedSignalMax;
r.corrected_signal_sum=r.signal_sum-r.background_mean*numel(sv);
r.corrected_signal_integral_world2=r.corrected_signal_sum*pixelArea;
r.sbr=sbr; r.cnr=cnr;
r.weighted_centroid_x=weightedX; r.weighted_centroid_y=weightedY;
r.has_signal=double(~isempty(sv));
r.pixel_spacing_y_mm=spacing(1); r.pixel_spacing_x_mm=spacing(2);
r.target_area_mm2=numel(v)*pixelArea;
r.signal_area_mm2=numel(sv)*pixelArea;
r.background_area_mm2=numel(b)*pixelArea;
r.spatial_unit=spatialUnit;
T=struct2table(r);
end
