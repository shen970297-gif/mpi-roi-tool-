% Run this script from the MATLAB Editor to launch the MPI ROI tool.
toolFolder=fileparts(mfilename('fullpath'));
addpath(toolFolder);
app=mpi_roi_app();
