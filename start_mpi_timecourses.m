% 在 MATLAB 中打开本脚本并点击“运行”。不需要打开 ROI 分析窗口。
toolFolder=fileparts(mfilename('fullpath'));
addpath(toolFolder);
dataDir=fullfile(toolFolder,'results','m4'); % 改成其他动物目录即可复用
[timecourseData,timecourseOutput]=plot_mpi_timecourses(dataDir);
