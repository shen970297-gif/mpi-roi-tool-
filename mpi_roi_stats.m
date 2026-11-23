function s = mpi_roi_stats(data,mask,spacing,background,thresholdMode,thresholdK,fixedThreshold)
%MPI_ROI_STATS Statistics of finite samples; zeros and negatives are retained.
% spacing = [row_mm column_mm]. NaN means physical area is unknown.
% background = [] or logical mask. SD is sample SD (N-1).
if nargin<3, spacing=[NaN NaN]; end
if nargin<4, background=[]; end
if nargin<5, thresholdMode='background'; end
if nargin<6, thresholdK=2; end
if nargin<7, fixedThreshold=0; end
assert(ismember(thresholdMode,{'background','fixed'}),'Invalid threshold mode.');
validateattributes(thresholdK,{'numeric'},{'scalar','real','finite','nonnegative'});
validateattributes(fixedThreshold,{'numeric'},{'scalar','real','finite'});
validateattributes(data,{'numeric'},{'real','2d','nonempty'});
assert(islogical(mask) && isequal(size(data),size(mask)),'Mask must be logical and match image size.');
validateattributes(spacing,{'numeric'},{'real','vector','numel',2});
if ~isempty(background)
    assert(islogical(background) && isequal(size(data),size(background)), ...
        'Background mask must be logical and match image size.');
end
valid=mask & isfinite(data); v=double(data(valid));
s=struct('Pixels',nnz(mask),'ValidPixels',numel(v),'ExcludedPixels',nnz(mask)-numel(v), ...
    'Area_mm2',NaN,'Mean',NaN,'Sum',NaN,'Median',NaN,'SD',NaN, ...
    'Min',NaN,'Max',NaN,'NonzeroPixels',nnz(v), ...
    'BackgroundN',0,'BackgroundMean',NaN,'BackgroundSD',NaN, ...
    'CorrectedMean',NaN,'CorrectedSum',NaN,'SNR',NaN,'BackgroundOverlap',0, ...
    'ThresholdMode',string(thresholdMode),'ThresholdK',thresholdK,'FixedThreshold',fixedThreshold, ...
    'Threshold',NaN,'SignalPixels',NaN,'SignalArea_mm2',NaN,'SignalAreaPct',NaN, ...
    'SignalMean',NaN,'SignalMax',NaN,'SignalSum',NaN, ...
    'CorrectedSignalSum',NaN,'CorrectedSignalIntegral_mm2',NaN);
if all(isfinite(spacing)) && all(spacing>0), s.Area_mm2=nnz(mask)*prod(spacing); end
if ~isempty(v)
    s.Mean=mean(v); s.Sum=sum(v); s.Median=median(v);
    s.Min=min(v); s.Max=max(v);
    if numel(v)>1, s.SD=std(v,0); end
end
if ~isempty(background)
    b=double(data(background & isfinite(data))); s.BackgroundN=numel(b);
    s.BackgroundOverlap=nnz(mask & background);
    if ~isempty(b)
        s.BackgroundMean=mean(b);
        if numel(b)>1, s.BackgroundSD=std(b,0); end
        if strcmp(thresholdMode,'background')
            sd=0; if numel(b)>1, sd=s.BackgroundSD; end
            s.Threshold=s.BackgroundMean+thresholdK*sd;
        else
            s.Threshold=fixedThreshold;
        end
        signal=v(v>=s.Threshold);
        s.SignalPixels=numel(signal);
        if ~isempty(v), s.SignalAreaPct=100*s.SignalPixels/numel(v); end
        if all(isfinite(spacing)) && all(spacing>0)
            s.SignalArea_mm2=s.SignalPixels*prod(spacing);
        end
        s.SignalSum=sum(signal);
        if s.BackgroundOverlap==0
            s.CorrectedSignalSum=s.SignalSum-s.BackgroundMean*s.SignalPixels;
        end
        if isfinite(s.SignalArea_mm2)
            s.CorrectedSignalIntegral_mm2=s.CorrectedSignalSum*prod(spacing);
        end
        if ~isempty(signal)
            s.SignalMean=mean(signal); s.SignalMax=max(signal);
        end
        % Overlapping background is invalid for independent background correction.
        if s.BackgroundOverlap==0 && ~isempty(v)
            s.CorrectedMean=s.Mean-s.BackgroundMean;
            s.CorrectedSum=s.Sum-numel(v)*s.BackgroundMean;
            if s.BackgroundSD>0, s.SNR=s.CorrectedMean/s.BackgroundSD; end
        end
    end
end
end
