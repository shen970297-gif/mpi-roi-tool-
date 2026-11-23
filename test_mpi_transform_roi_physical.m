function test_mpi_transform_roi_physical
% Synthetic geometry check; no measured data or UI required.
sourceSize=[100 120]; sourceSpacing=[.2 .3];
targetSize=[180 200]; targetSpacing=[.15 .1];
sourceArea=prod(sourceSpacing); targetArea=prod(targetSpacing);
def=struct('Name','polygon','Shape','polygon', ...
    'Position',[40 30;50 30;50 40;40 40]);
mapped=mpi_transform_roi_physical(def,sourceSize,sourceSpacing,targetSize,targetSpacing);
a=polyarea(def.Position(:,1),def.Position(:,2))*sourceArea;
b=polyarea(mapped.Position(:,1),mapped.Position(:,2))*targetArea;
assert(abs(a-b)<1e-10);
def=struct('Name','ellipse','Shape','ellipse', ...
    'Position',struct('Center',[60 50],'SemiAxes',[8 5],'RotationAngle',30));
mapped=mpi_transform_roi_physical(def,sourceSize,sourceSpacing,targetSize,targetSpacing);
a=pi*prod(def.Position.SemiAxes)*sourceArea;
b=pi*prod(mapped.Position.SemiAxes)*targetArea;
assert(abs(a-b)<1e-10);
def=struct('Name','rectangle','Shape','rectangle', ...
    'Position',struct('Position',[40 30 10 6],'RotationAngle',30));
mapped=mpi_transform_roi_physical(def,sourceSize,sourceSpacing,targetSize,targetSpacing);
assert(strcmp(mapped.Shape,'polygon'));
a=10*6*sourceArea;
b=polyarea(mapped.Position(:,1),mapped.Position(:,2))*targetArea;
assert(abs(a-b)<1e-10);
disp('PASS: ROI geometry preserves physical area across pixel spacings.');
end
