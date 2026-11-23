function mpi_ensure_utf8_bom(file)
%MPI_ENSURE_UTF8_BOM Make CSV readable as UTF-8 in Excel.
[fid,msg]=fopen(file,'rb');
if fid<0, error('MPI:Export','Cannot read CSV: %s',msg); end
closer=onCleanup(@()fclose(fid));
bytes=fread(fid,Inf,'*uint8');
clear closer;
bom=uint8([239;187;191]);
if numel(bytes)>=3 && isequal(bytes(1:3),bom), return; end
[fid,msg]=fopen(file,'wb');
if fid<0, error('MPI:Export','Cannot write CSV: %s',msg); end
closer=onCleanup(@()fclose(fid));
count=fwrite(fid,[bom;bytes],'uint8');
if count~=numel(bytes)+3, error('MPI:Export','Incomplete CSV write.'); end
end
