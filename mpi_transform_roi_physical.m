function def=mpi_transform_roi_physical(def,sourceSize,sourceSpacing,targetSize,targetSpacing)
%MPI_TRANSFORM_ROI_PHYSICAL Preserve ROI geometry in mm across image grids.
% Both image centers are treated as the same physical point; this is not registration.
validateattributes(sourceSize,{'numeric'},{'vector','numel',2,'positive'});
validateattributes(targetSize,{'numeric'},{'vector','numel',2,'positive'});
validateattributes(sourceSpacing,{'numeric'},{'vector','numel',2,'positive','finite'});
validateattributes(targetSpacing,{'numeric'},{'vector','numel',2,'positive','finite'});
sx=sourceSpacing(2)/targetSpacing(2);
sy=sourceSpacing(1)/targetSpacing(1);
sourceCenter=[(sourceSize(2)+1)/2,(sourceSize(1)+1)/2];
targetCenter=[(targetSize(2)+1)/2,(targetSize(1)+1)/2];
map=@(points) (points-sourceCenter).*[sx sy]+targetCenter;
switch def.Shape
    case {'polygon','freehand'}
        def.Position=map(double(def.Position));
    case 'ellipse'
        p=def.Position;
        p.Center=map(double(p.Center));
        angle=double(p.RotationAngle)*pi/180;
        rotation=[cos(angle) -sin(angle);sin(angle) cos(angle)];
        stretch=diag([sx sy]);
        axes2=diag(double(p.SemiAxes(:)).^2);
        covariance=stretch*rotation*axes2*rotation'*stretch;
        [vectors,values]=eig(covariance);
        [squaredAxes,order]=sort(diag(values),'descend');
        p.SemiAxes=sqrt(max(squaredAxes,0))';
        direction=vectors(:,order(1));
        p.RotationAngle=atan2d(direction(2),direction(1));
        def.Position=p;
    case 'rectangle'
        p=def.Position;
        angle=double(p.RotationAngle);
        if mod(angle,180)==0
            q=double(p.Position);
            first=map(q(1:2));
            p.Position=[first,q(3)*sx,q(4)*sy];
            def.Position=p;
        else
            % Anisotropic scaling turns a rotated rectangle into a parallelogram.
            q=double(p.Position);
            center=q(1:2)+q(3:4)/2;
            corners=[-q(3)/2 -q(4)/2;q(3)/2 -q(4)/2; ...
                q(3)/2 q(4)/2;-q(3)/2 q(4)/2];
            rotation=[cosd(angle) -sind(angle);sind(angle) cosd(angle)];
            def.Shape='polygon';
            def.Position=map(corners*rotation'+center);
        end
    otherwise
        error('MPI:ROI','Unsupported ROI shape for physical transfer.');
end
end
