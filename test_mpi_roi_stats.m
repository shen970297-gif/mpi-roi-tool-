function test_mpi_roi_stats
% Optional: run this yourself in MATLAB. Does not access measured data or open UI.
a=[-2 0 2;4 NaN Inf]; m=true(size(a));
s=mpi_roi_stats(a,m,[.25 .5]);
assert(s.Pixels==6 && s.ValidPixels==4 && s.ExcludedPixels==2);
assert(s.Sum==4 && s.Mean==1 && s.Median==1);
assert(s.Min==-2 && s.Max==4 && s.NonzeroPixels==3);
assert(abs(s.SD-sqrt(20/3))<1e-12);
assert(s.Area_mm2==.75);
s=mpi_roi_stats(a,false(size(a)));
assert(s.ValidPixels==0 && isnan(s.Mean) && isnan(s.Sum));
a=[10 20;2 4]; target=logical([1 1;0 0]); bg=~target;
s=mpi_roi_stats(a,target,[NaN NaN],bg);
assert(s.BackgroundMean==3 && s.CorrectedMean==12 && s.CorrectedSum==24);
assert(abs(s.SNR-12/sqrt(2))<1e-12 && isnan(s.Area_mm2));
% Background subtraction counts finite samples only and preserves negative results.
s=mpi_roi_stats([10 NaN;2 4],target,[.25 .5],bg);
assert(s.ValidPixels==1 && s.CorrectedSum==7);
s=mpi_roi_stats([1 1;2 4],target,[.25 .5],bg);
assert(s.CorrectedSum==-4);
s=mpi_roi_stats(a,target,[1 1],target);
assert(s.BackgroundOverlap==2 && isnan(s.CorrectedSum));
s=mpi_roi_stats(a,target,[1 1],false(size(a)));
assert(s.BackgroundN==0 && isnan(s.CorrectedSum));
s=mpi_roi_stats([3 3;3 3],target,[1 1],bg);
assert(s.CorrectedSum==0 && isnan(s.SNR));
s=mpi_roi_stats([7 NaN],true(1,2));
assert(s.Sum==7 && isnan(s.SD));
% Same threshold rule as the Python MPI quantification tool.
a=[10 20;2 4]; target=logical([1 1;0 0]); bg=~target;
s=mpi_roi_stats(a,target,[.25 .5],bg,'background',2,0);
assert(abs(s.Threshold-(3+2*sqrt(2)))<1e-12);
assert(s.SignalPixels==2 && s.SignalSum==30 && s.CorrectedSignalSum==24);
assert(s.SignalAreaPct==100 && s.SignalArea_mm2==.25);
s=mpi_roi_stats(a,target,[.25 .5],bg,'fixed',15,15);
assert(s.Threshold==15 && s.SignalPixels==1 && s.SignalSum==20);
assert(s.CorrectedSignalSum==17 && s.SignalAreaPct==50);
s=mpi_roi_stats(a,target,[1 1],bg,'fixed',2,25);
assert(s.SignalPixels==0 && s.SignalSum==0 && isnan(s.SignalMean));
disp('PASS: ROI statistics, finite-value policy, area and background correction.');
end
