function [data, meta] = mpi_read_image(file)
%MPI_READ_IMAGE Read one quantitative 2-D image, preserving signed values.
file = char(file);
[~,~,ext] = fileparts(file);
meta = struct('Source',file,'Format',lower(ext),'PixelSpacing',[NaN NaN], ...
    'Slope',1,'Intercept',0,'Units','a.u. (unverified)', ...
    'SpacingSource','unknown','PhotometricInterpretation','', ...
    'StoredClass','','StoredMin',NaN,'StoredMax',NaN);
switch lower(ext)
    case '.dcm'
        info = dicominfo(file);
        if isfield(info,'SamplesPerPixel') && info.SamplesPerPixel ~= 1
            error('MPI:Color','Color DICOM is not a quantitative scalar image.');
        end
        if isfield(info,'NumberOfFrames') && str2double(string(info.NumberOfFrames)) > 1
            error('MPI:Frames','This version supports single-frame 2-D images only.');
        end
        if isfield(info,'ModalityLUTSequence') || isfield(info,'RealWorldValueMappingSequence')
            error('MPI:Mapping','Nonlinear/additional value mapping needs a dedicated reader.');
        end
        raw = dicomread(info);
        if isfield(info,'RescaleSlope'), meta.Slope = double(info.RescaleSlope); end
        if isfield(info,'RescaleIntercept'), meta.Intercept = double(info.RescaleIntercept); end
        if ~isscalar(meta.Slope) || ~isscalar(meta.Intercept) || ...
                ~isfinite(meta.Slope) || ~isfinite(meta.Intercept) || meta.Slope == 0
            error('MPI:Scaling','Invalid DICOM rescale parameters.');
        end
        if isfield(info,'PixelSpacing')
            ps = double(info.PixelSpacing(:)');
            if numel(ps)==2 && all(isfinite(ps)) && all(ps>0)
                meta.PixelSpacing=ps; meta.SpacingSource='DICOM PixelSpacing (row,column), mm';
            end
        end
        if isfield(info,'PhotometricInterpretation')
            meta.PhotometricInterpretation=char(info.PhotometricInterpretation);
        end
        data = double(raw)*meta.Slope + meta.Intercept;
        % Padding denotes missing image samples, not zero signal.
        if isfield(info,'PixelPaddingValue')
            pad1=double(info.PixelPaddingValue); pad2=pad1;
            if isfield(info,'PixelPaddingRangeLimit'), pad2=double(info.PixelPaddingRangeLimit); end
            data(double(raw)>=min(pad1,pad2) & double(raw)<=max(pad1,pad2))=NaN;
        end
        if isfield(info,'RescaleType') && ~isempty(info.RescaleType)
            meta.Units=['DICOM RescaleType: ' char(info.RescaleType) ' (not mass-calibrated)'];
        end
    case {'.tif','.tiff'}
        info=imfinfo(file);
        if numel(info)~=1
            error('MPI:Frames','Multi-page TIFF is not supported in this 2-D version.');
        end
        [raw,map]=imread(file);
        if ~isempty(map) || ~ismatrix(raw)
            error('MPI:Color','RGB/indexed images cannot be used as quantitative scalar images.');
        end
        data=double(raw);
        meta.Units='TIFF stored values (scaling unverified)';
    otherwise
        error('MPI:Format','Choose a DICOM (.dcm) or scalar TIFF image.');
end
if ~ismatrix(data) || isempty(data) || ~isreal(data)
    error('MPI:Dimensions','Expected a nonempty real 2-D image.');
end
if ~any(isfinite(data(:))), error('MPI:Empty','Image has no finite samples.'); end
meta.StoredClass=class(raw);
meta.StoredMin=min(double(raw(:))); meta.StoredMax=max(double(raw(:)));
meta.ImageSize=size(data);
d=dir(file); meta.FileBytes=d.bytes; meta.FileModified=d.date;
end
