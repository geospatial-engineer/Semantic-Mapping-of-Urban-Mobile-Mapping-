clc; clear; close all;

%% =========================================================
%  SEMANTIC QUERY TOOL
%  Search the point cloud by category, brand, or keyword.
%
%  Examples:
%    restaurant        → all restaurants
%    pizza             → keyword resolved to RESTAURANT
%    decathlon         → brand name search (low-conf OK)
%    jumbo             → brand/keyword search
%    all               → show every detection
%    list              → print what is in the dataset
%    exit              → quit
% =========================================================

%% =========================
% USER SETTINGS
%% =========================
panoDir         = 'C.............................\pano images\';
jsonFile        = fullfile(panoDir, 'ocr_semantic_results.json');
orientationFile = '...............................\wpk.csv';
lasFile         = '...............................\point cloud us.las';
W = 10240;
H = 5120;

params = struct();
params.tMin       = 5;
params.tMax       = 80;
params.hitRadius  = 1.0;
params.paintRadius = 2.0;
params.minCand    = 10;
params.stepCoarse      = 0.5;
params.stepFine        = 0.05; 
params.planeThickness  = 0.25;
 
params.minFusionConf   = 0.4;    % default — relaxed for brand queries
params.labelFloatZ     = 5.0;
params.mergeRadius     = 13.0;

%% =========================
% KEYWORD → CATEGORY MAP
%% =========================
taxonomy = {

% ---------------- RESTAURANTS / FOOD ----------------
'restaurant',   'RESTAURANT';  'grill',        'RESTAURANT';
'bar',          'RESTAURANT';  'cafe',         'RESTAURANT';
'coffee',       'RESTAURANT';  'pizza',        'RESTAURANT';
'burger',       'RESTAURANT';  'steak',        'RESTAURANT';
'bistro',       'RESTAURANT';  'eatery',       'RESTAURANT';
'kitchen',      'RESTAURANT';  'diner',        'RESTAURANT';
'sushi',        'RESTAURANT';  'tapas',        'RESTAURANT';
'pizzeria',     'RESTAURANT';  'bakery',       'RESTAURANT';
'sandwich',     'RESTAURANT';  'bbq',          'RESTAURANT';
'tacos',        'RESTAURANT';  'mexican',      'RESTAURANT';
'grillhouse',   'RESTAURANT';  'steakhouse',   'RESTAURANT';
'pasta',        'RESTAURANT';  'donuts',       'RESTAURANT';

% major brands
'starbucks',    'RESTAURANT';
'mcdonalds',    'RESTAURANT';
'subway',       'RESTAURANT';
'burger king',  'RESTAURANT';
'taco bell',    'RESTAURANT';
'kfc',          'RESTAURANT';
'chipotle',     'RESTAURANT';
'wendys',       'RESTAURANT';
'dunkin',       'RESTAURANT';

% ---------------- SUPERMARKETS ----------------
'supermarket',  'SUPERMARKET';
'grocery',      'SUPERMARKET';
'market',       'SUPERMARKET';

% US chains
'walmart',      'SUPERMARKET';
'target',       'SUPERMARKET';
'whole foods',  'SUPERMARKET';
'trader joes',  'SUPERMARKET';
'costco',       'SUPERMARKET';
'safeway',      'SUPERMARKET';
'kroger',       'SUPERMARKET';

% ---------------- CLOTHING ----------------
'fashion',      'CLOTHING';
'clothing',     'CLOTHING';
'boutique',     'CLOTHING';
'apparel',      'CLOTHING';
'outfitters',   'CLOTHING';
'outlet',       'CLOTHING';

% clothing brands
'nike',         'CLOTHING';
'adidas',       'CLOTHING';
'levis',        'CLOTHING';
'gap',          'CLOTHING';
'h&m',          'CLOTHING';
'zara',         'CLOTHING';
'uniqlo',       'CLOTHING';

% ---------------- SPORTS ----------------
'sport',        'SPORTS';
'sportswear',   'SPORTS';
'fitness',      'SPORTS';
'gym',          'SPORTS';
'athletics',    'SPORTS';

% brands
'decathlon',    'SPORTS';
'reebok',       'SPORTS';
'under armour', 'SPORTS';

% ---------------- SHOES ----------------
'shoes',        'SHOES';
'footwear',     'SHOES';
'sneakers',     'SHOES';
'boots',        'SHOES';

% chains
'foot locker',  'SHOES';
'finish line',  'SHOES';

% ---------------- PHARMACY ----------------
'pharmacy',     'PHARMACY';
'drugstore',    'PHARMACY';
'medical',      'PHARMACY';

% chains
'cvs',          'PHARMACY';
'walgreens',    'PHARMACY';
'rite aid',     'PHARMACY';

% ---------------- BANK ----------------
'bank',         'BANK';
'atm',          'BANK';
'credit union', 'BANK';

% chains
'chase',        'BANK';
'wells fargo',  'BANK';
'bank of america','BANK';
'citibank',     'BANK';

% ---------------- HAIRDRESSER ----------------
'hair',         'HAIRDRESSER';
'hair salon',   'HAIRDRESSER';
'haircut',      'HAIRDRESSER';
'barber',       'HAIRDRESSER';
'barbershop',   'HAIRDRESSER';
'salon',        'HAIRDRESSER';

% ---------------- RETAIL ----------------
'store',        'RETAIL';
'shop',         'RETAIL';
'electronics',  'RETAIL';
'phone',        'RETAIL';
'mobile',       'RETAIL';
'books',        'RETAIL';
 

% chains
'best buy',     'RETAIL';
'apple',        'RETAIL';
'att',          'RETAIL';
'tmobile',      'RETAIL';
'verizon',      'RETAIL';

% ---------------- BEAUTY / NAIL SALON ----------------
'beauty',       'BEAUTY';
'spa',          'BEAUTY';
'nails',        'BEAUTY';
'nail salon',   'BEAUTY';
'nail spa',     'BEAUTY';
'beauty salon', 'BEAUTY';

% ---------------- DRY CLEANERS ----------------
'cleaners',        'DRYCLEAN';
'dry cleaners',    'DRYCLEAN';
'dry cleaning',    'DRYCLEAN';
'laundry',         'DRYCLEAN';

% ---------------- REAL ESTATE ----------------
'realty',      'REALESTATE';
'realtor',     'REALESTATE';
'real estate', 'REALESTATE';
'properties',  'REALESTATE';

% ---------------- REAL ESTATE ----------------
'realty',      'REALESTATE';
'realtor',     'REALESTATE';
'real estate', 'REALESTATE';
'properties',  'REALESTATE';
% ---------------- FLORIST ----------------
'florist',      'FLORIST';
'flowers',      'FLORIST';
'flower shop',  'FLORIST';
'floral',       'FLORIST';


};
 
kwMap = containers.Map(taxonomy(:,1), taxonomy(:,2));

%% =========================
% LABEL → COLOR MAP
%% =========================
labelColors = containers.Map( ...
    {'RESTAURANT','SUPERMARKET','CLOTHING','SPORTS', ...
     'SHOES','PHARMACY','BANK','HAIRDRESSER','RETAIL','CUSTOM'}, ...
    {[1.00 0.10 0.10], [0.10 0.80 0.10], [1.00 0.50 0.00], ...
     [0.00 0.60 1.00], [0.80 0.00 0.80], [0.00 0.90 0.90], ...
     [1.00 1.00 0.00], [1.00 0.40 0.70], [0.60 0.40 0.20], ...
     [1.00 1.00 1.00]} ...
);

%% =========================
% LOAD ALL DATA  (once)
%% =========================
fprintf('Loading JSON...\n');
Detections = jsondecode(fileread(jsonFile));

fprintf('Loading orientation...\n');
opts = detectImportOptions(orientationFile);
opts = setvartype(opts, 'ImageId', 'string');
Tori = readtable(orientationFile, opts);
Tori.ImageId = strtrim(Tori.ImageId);
imageIdMap = containers.Map(Tori.ImageId, num2cell(1:height(Tori)));

fprintf('Loading LAS...\n');
lasR   = lasFileReader(lasFile);
pc     = readPointCloud(lasR);
pts    = double(pc.Location);
pc_ds  = pcdownsample(pointCloud(pts), 'gridAverage', 0.20);
pts_ds = double(pc_ds.Location);
kd     = KDTreeSearcher(pts_ds);

fprintf('Precomputing ds→full map...\n');
dsToFull = knnsearch(pts, pts_ds);

% Base colors
if ~isempty(pc.Color)
    rc = double(pc.Color);
    baseColors = rc / (max(rc(:)) > 255) * (1/65535 - 1/255) + rc/255;
    if max(rc(:)) > 255, baseColors = rc/65535; else, baseColors = rc/255; end
    fprintf('Using LAS RGB.\n');
else
    z = pts(:,3); z = (z-min(z))/(max(z)-min(z)+eps);
    cmap = parula(256); idxZ = max(1,min(256,round(1+z*255)));
    baseColors = cmap(idxZ,:);
    fprintf('Using height colours.\n');
end

fprintf('\nData ready.\n');

%% =========================
% QUERY LOOP
%% =========================
fprintf('\n============================================\n');
fprintf('  SEMANTIC QUERY TOOL\n');
fprintf('  category:  restaurant  bank  sports\n');
fprintf('  keyword:   pizza  kapper  apotheek\n');
fprintf('  brand:     decathlon  jumbo  rabobank\n');
fprintf('  commands:  all  list  exit\n');
fprintf('============================================\n\n');

while true

    rawQuery = strtrim(lower(input('Search > ', 's')));
    if isempty(rawQuery), continue; end

    % Reset fusion threshold to default at the start of every query
    params.minFusionConf = 0.4;

    % ---- Special commands ----------------------------------------
    if strcmp(rawQuery, 'exit')
        fprintf('Goodbye.\n'); break;
    end

    if strcmp(rawQuery, 'list')
        fprintf('\nCategories detected in dataset:\n');
        for i = 1:numel(Detections)
            lbl = char(Detections(i).semanticLabel);
            if ~ismember(lbl, {'UNKNOWN','NO_TEXT',''})
                fprintf('  %-15s', lbl);
            end
        end
        fprintf('\n\nBrands / names detected:\n');
        shownBrands = {};
        for i = 1:numel(Detections)
            if isfield(Detections(i),'brandName')
                bn = strtrim(lower(char(Detections(i).brandName)));
                if strlength(bn) > 0 && ~ismember(bn, shownBrands)
                    fprintf('  %-25s [%s]\n', bn, Detections(i).semanticLabel);
                    shownBrands{end+1} = bn;  
                end
            end
        end
        fprintf('\n'); continue;
    end

    % ---- Resolve query type & set match function -----------------
    queryUpper   = upper(rawQuery);
    isBrandQuery = false;

    if strcmp(rawQuery, 'all')
        % Show every non-trivial detection
        matchFn      = @(lbl, brand) ~ismember(lbl, {'UNKNOWN','NO_TEXT',''});
        queryDisplay = 'ALL FEATURES';

    elseif isKey(labelColors, queryUpper)
        % User typed a category name directly  e.g. "restaurant"
        matchFn      = @(lbl, brand) strcmp(lbl, queryUpper);
        queryDisplay = queryUpper;

    elseif isKey(kwMap, rawQuery)
        % Keyword resolves to a category  e.g. "pizza" → RESTAURANT
        resolvedCat  = kwMap(rawQuery);
        matchFn      = @(lbl, brand) strcmp(lbl, resolvedCat);
        queryDisplay = sprintf('%s  [keyword → %s]', queryUpper, resolvedCat);

    else
        % Brand / free-text: search brandName field AND semanticLabel
        % Relax paint threshold — user is explicit, show even conf=0.25
        matchFn = @(lbl, brand) ~isempty(regexp(brand, ['\<', rawQuery, '\>'], 'once'));
        queryDisplay         = sprintf('"%s"  [brand search]', rawQuery);
        isBrandQuery         = true;
        params.minFusionConf = 0.10;   % relaxed for explicit brand lookup
    end

    % ---- Collect matching detection indices ----------------------
    hits = [];
    for p = 1:numel(Detections)
        lbl   = char(Detections(p).semanticLabel);
        brand = '';
        if isfield(Detections(p), 'brandName')
            brand = strtrim(lower(char(Detections(p).brandName)));
        end
        conf = double(Detections(p).semanticConfidence);
        if conf > 0 && matchFn(lbl, brand)
            hits(end+1) = p;  
        end
    end

    if isempty(hits)
        fprintf('  No detections found for "%s".\n\n', rawQuery);
        continue;
    end
    fprintf('\n  Found %d detection(s) matching %s\n', numel(hits), queryDisplay);

    % ---- Project detections onto point cloud ---------------------
    colors     = baseColors;
    paintConf  = zeros(size(pts,1), 1);
    paintVotes = zeros(size(pts,1), 1);
    rawCentroids = [];
    rawConfs_q   = [];
    rawLabels_q  = {};
    rawBrands_q  = {};

    for hi = 1:numel(hits)
        p     = hits(hi);
        lbl   = char(Detections(p).semanticLabel);
        conf  = double(Detections(p).semanticConfidence);
        brand = '';
        if isfield(Detections(p),'brandName')
            brand = strtrim(char(Detections(p).brandName));
        end
% ---------------------------------------------------------
% SHOW PANORAMA WITH OCR DETECTION BOXES
% ---------------------------------------------------------

imgFile = fullfile(panoDir, char(Detections(p).image));

if exist(imgFile,'file')

    img = imread(imgFile);

    figure('Name', sprintf('Panorama: %s', Detections(p).image));
    imshow(img); hold on;

    bboxes = Detections(p).bboxes;

    % Draw all OCR boxes
    for bi = 1:size(bboxes,1)

        rectangle('Position', bboxes(bi,:), ...
                  'EdgeColor',[0 1 1], ...
                  'LineWidth',1.5);

    end

    % Highlight main detection
    if ~isempty(bboxes)

        rectangle('Position', bboxes(1,:), ...
                  'EdgeColor','red', ...
                  'LineWidth',3);

        txt = sprintf('%s (%s)', upper(brand), lbl);

        text(bboxes(1,1), bboxes(1,2)-10, txt, ...
            'Color','yellow', ...
            'FontSize',12, ...
            'FontWeight','bold', ...
            'BackgroundColor','black', ...
            'Interpreter','none');

    end

    hold off;

end
        imageID = erase(string(Detections(p).image), '.jpg');
        if ~isKey(imageIdMap, imageID), continue; end
        row = imageIdMap(imageID);

        C = [Tori.East(row); Tori.North(row); Tori.Height(row)];

  Rwc = [
    Tori.r11(row) Tori.r12(row) Tori.r13(row);
    Tori.r14(row) Tori.r15(row) Tori.r16(row);
    Tori.r17(row) Tori.r18(row) Tori.r19(row)
];
        bboxes = Detections(p).bboxes;
        detectionPatchCorners = [];

        for i = 1:size(bboxes,1)
            bbox4 = bboxXYWH_to_corners(bboxes(i,:));
            [patch3D, ok] = bboxToFacadePatch3D_US(bbox4, W, H, C', Rwc, kd, pts_ds, params);
            if ~ok, continue; end

            idxPaint = paintPointsNearPatch(pts_ds, kd, patch3D, params);
            if isempty(idxPaint), continue; end

            idxFull = dsToFull(idxPaint);
            paintConf(idxFull)  = paintConf(idxFull)  + conf;
            paintVotes(idxFull) = paintVotes(idxFull) + 1;
            detectionPatchCorners = [detectionPatchCorners; patch3D];  
        end

       if ~isempty(detectionPatchCorners)

    % reshape Nx3 just in case multiple patches were added
    ptsPatch = reshape(detectionPatchCorners, [], 3);

    % use center of patch instead of corner mean
    patchCenter = mean(ptsPatch,1);

    rawCentroids(end+1,:) = patchCenter;
    rawConfs_q(end+1)     = conf;
    rawLabels_q{end+1}    = lbl;
    rawBrands_q{end+1}    = brand;

end
    end

    % ---- Apply paint color ---------------------------------------
    avgConf           = zeros(size(pts,1), 1);
    hasVotes          = paintVotes > 0;
    avgConf(hasVotes) = paintConf(hasVotes) ./ paintVotes(hasVotes);
    paintMask         = avgConf >= params.minFusionConf;

    uniqueHitLabels = unique(rawLabels_q);
    if isscalar(uniqueHitLabels) && isKey(labelColors, uniqueHitLabels{1})
        paintRGB = labelColors(uniqueHitLabels{1});
    else
        paintRGB = [1 1 1];
    end

    colors(paintMask,:) = repmat(paintRGB, sum(paintMask), 1);
    fprintf('  Painted %d points.\n', sum(paintMask));

    % ---- Merge nearby centroids of same label --------------------
    mergedCentroids = [];
    mergedConfs_m   = [];
    mergedLabels_m  = {};
    mergedBrands_m  = {};

    uniqueQL = unique(rawLabels_q);
    for u = 1:numel(uniqueQL)
        ulbl  = uniqueQL{u};
        mask  = strcmp(rawLabels_q, ulbl);
        pts3  = rawCentroids(mask,:);
        cfs   = rawConfs_q(mask);
        brds  = rawBrands_q(mask);
        assigned = false(size(pts3,1),1);

        for i = 1:size(pts3,1)
            if assigned(i), continue; end
            dxy     = sqrt((pts3(:,1)-pts3(i,1)).^2 + (pts3(:,2)-pts3(i,2)).^2);
            cluster = (~assigned) & (dxy <= params.mergeRadius);
            assigned(cluster) = true;

            w         = cfs(cluster); w = w(:)'/sum(w);
            mergedXYZ = w * pts3(cluster,:);

            % Pick the brand name from the highest-confidence detection in cluster
            [~, bestIdx]  = max(cfs(cluster));
            clusterBrands = brds(cluster);
            bestBrand     = clusterBrands{bestIdx};

            mergedCentroids(end+1,:) = mergedXYZ;            
            mergedConfs_m(end+1)     = max(cfs(cluster));    
            mergedLabels_m{end+1}    = ulbl;                  
            mergedBrands_m{end+1}    = bestBrand;             
        end
    end

    fprintf('  %d raw → %d unique location(s) after merging.\n\n', ...
        numel(rawLabels_q), numel(mergedLabels_m));

    % ---- Render --------------------------------------------------
    figure('Name', sprintf('Query: %s', queryDisplay));
    ax = axes('Parent', gcf);
    pcshow(pts, colors, 'Parent', ax);
    title(ax, sprintf('Query: %s   (%d location(s))', queryDisplay, numel(mergedLabels_m)), ...
        'Interpreter', 'none');
    hold(ax, 'on');

    floatZ = params.labelFloatZ;

    for k = 1:numel(mergedLabels_m)
        cx    = mergedCentroids(k,1);
        cy    = mergedCentroids(k,2);
        cz    = mergedCentroids(k,3);
        lbl   = mergedLabels_m{k};
        cf    = mergedConfs_m(k);
        brand = mergedBrands_m{k};

        labelZ = cz + floatZ;

        % Color: use label color
        rgb = paintRGB;
        if isKey(labelColors, lbl), rgb = labelColors(lbl); end

        % Build label text:
        %   brand search  → show brand name + category
        %   category/kw   → show category name
        if isBrandQuery && strlength(brand) > 0
            labelTxt = sprintf('%s  [%s]  (%.2f)', upper(brand), lbl, cf);
        else
            labelTxt = sprintf('%s  (%.2f)', lbl, cf);
        end

        % Arrow
        quiver3(ax, cx, cy, labelZ, 0, 0, -floatZ+0.5, 0, ...
            'Color', rgb, 'LineWidth', 1.8, 'MaxHeadSize', 0.6);

        % Dot at facade
        plot3(ax, cx, cy, cz, 'o', ...
            'MarkerSize', 10, 'MarkerFaceColor', rgb, ...
            'MarkerEdgeColor', 'white', 'LineWidth', 1.5);

        % Floating text
        text(ax, cx, cy, labelZ+0.3, labelTxt, ...
            'Color',               'white',    ...
            'FontSize',            11,          ...
            'FontWeight',          'bold',      ...
            'HorizontalAlignment', 'center',    ...
            'VerticalAlignment',   'bottom',    ...
            'BackgroundColor',     [0 0 0 0.7], ...
            'EdgeColor',           rgb,         ...
            'LineWidth',           1.5,         ...
            'Interpreter',         'none');

        fprintf('  [%d] %-15s brand="%-20s"  conf=%.2f  XY=[%.1f, %.1f]\n', ...
            k, lbl, brand, cf, cx, cy);
    end

    hold(ax, 'off');
    rotate3d(ax, 'off');

    %% --- Export to CloudCompare ---------------------------------
    % Exports two files per query:
    %  1. detected_labels.csv   — label positions (X Y Z Label Confidence)
    %     Open in CloudCompare: File → Open, set separator to comma,
    %     assign X/Y/Z columns, import scalar fields.
    %
    %  2. detected_points.txt   — painted LiDAR points with RGB
    %     Open in CloudCompare as XYZ + RGB point cloud.

    if ~isempty(mergedCentroids)
        % ---- Label positions CSV ----
        labelPts  = mergedCentroids;
        labelConf = mergedConfs_m(:);
        labelStr  = string(mergedLabels_m(:));

        % Use brand names where available, else label
       % Combine brand + category for queryable labels
labelDisplay = strings(numel(labelStr),1);

for k = 1:numel(labelStr)

    brand = strtrim(string(mergedBrands_m{k}));
    cat   = upper(string(labelStr(k)));

    if strlength(brand) > 0
        labelDisplay(k) = sprintf('%s (%s)', upper(brand), cat);
    else
        labelDisplay(k) = cat;
    end

end

        T = table( ...
    labelPts(:,1), labelPts(:,2), labelPts(:,3), ...
    labelConf, labelStr, labelDisplay, ...
    'VariableNames', {'X','Y','Z','Confidence','Category','SearchLabel'});
        csvFile = fullfile('C:\Luma paper\Experiment 2 ladybug US\pano images', ...
            sprintf('labels_%s.csv', regexprep(rawQuery, '[^a-zA-Z0-9]', '_')));
        writetable(T, csvFile);
        fprintf('  Labels exported → %s\n', csvFile);

        % ---- Painted point cloud TXT (XYZ RGB) ----
        paintedIdx = find(paintMask);
        if ~isempty(paintedIdx)
            ptsOut = pts(paintedIdx, :);
            rgbOut = round(colors(paintedIdx, :) * 255);

            txtFile = fullfile('C:\Luma paper\2nd test', ...
                sprintf('cloud_%s.txt', regexprep(rawQuery, '[^a-zA-Z0-9]', '_')));
            fid = fopen(txtFile, 'w');
            fprintf(fid, '//X Y Z R G B\n');
            for i = 1:size(ptsOut,1)
                fprintf(fid, '%.4f %.4f %.4f %d %d %d\n', ...
                    ptsOut(i,1), ptsOut(i,2), ptsOut(i,3), ...
                    rgbOut(i,1), rgbOut(i,2), rgbOut(i,3));
            end
            fclose(fid);
            fprintf('  Painted cloud exported → %s\n', txtFile);
        end
    else
        fprintf('  Nothing to export (no merged locations).\n');
    end

end % while


