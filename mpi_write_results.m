function mpi_write_results(T,out)
%MPI_WRITE_RESULTS Export native Excel plus UTF-8 CSV with an explicit BOM.
% XLSX stores Unicode directly; a CSV BOM helps Excel detect UTF-8 on open.
writetable(T,fullfile(out,'roi_statistics.xlsx'),'Sheet','ROI Statistics','UseExcel',false);
csvFile=fullfile(out,'roi_statistics.csv');
writetable(T,csvFile,'Encoding','UTF-8');
[fid,msg]=fopen(csvFile,'rb');
if fid<0, error('MPI:Export','Cannot read CSV: %s',msg); end
closer=onCleanup(@()fclose(fid));
bytes=fread(fid,Inf,'*uint8');
clear closer;
bom=uint8([239;187;191]);
if numel(bytes)>=3 && isequal(bytes(1:3),bom)
    return; % Do not duplicate a BOM already supplied by MATLAB.
end
[fid,msg]=fopen(csvFile,'wb');
if fid<0, error('MPI:Export','Cannot write CSV: %s',msg); end
closer=onCleanup(@()fclose(fid));
n=fwrite(fid,[bom;bytes],'uint8');
if n~=numel(bytes)+3, error('MPI:Export','Incomplete CSV write. Check available disk space.'); end
end
