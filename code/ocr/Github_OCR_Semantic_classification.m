function Github_OCR_Semantic_classification()
     
% OCR_Semantic_classification  — run as:  OCR_Semantic_classification()
%
% Detects text in panoramic images, classifies facilities using a
% two-tier keyword taxonomy with whole-word matching, extracts brand
% names, and exports results to JSON for the semantic fusion pipeline.

clc; close all;

%% =========================
% USER SETTINGS
%% =========================
panoDir         = '.............................\pano images\';
exts            = ["*.jpg","*.jpeg","*.png"];
minW            = 40;
minH            = 20;
maxBoxesPerPano = 60;
minOcrConf      = 0.50;
roiScale        = 2;
debugShowFirst  = true;

%% =========================
% KEYWORD TAXONOMY — two-tier
%% =========================
cats = buildTaxonomy();

%% =========================
% BRAND BLOCKLIST
% Words that look like brand names but are NOT.
% Includes: city names, Dutch/English common nouns, adjectives,
% prepositions, and any word that appears on generic Dutch signage.
%% =========================
brandBlocklist = {
'open','closed','welcome','please','thank','thanks','seafood','dinner','lunch','breakfast','grill','steak','pasta',...
'bbq','tacos','pizza','burger','sandwich','bagel','kitchen',...
'enter','exit','entrance','service','services',...
'sale','special','specials','offer','offers','deal',...
'best','fresh','daily','today','menu','breakfast','lunch','dinner',...
'market','store','shop','retail','center','plaza','mall',...
'company','inc','corp','corporation','llc','ltd',...
'food','foods','restaurant','grill','kitchen','dining',...
'cafe','coffee','bar','deli','pizza','burger','sandwich',...
'bakery','dessert','desserts','ice','cream','donut','donuts','bagel','bagels',...
'hours','opening','daily','monday','tuesday','wednesday','thursday','friday','saturday','sunday',...
'street','st','avenue','ave','road','rd','boulevard','blvd','lane','ln',...
'drive','dr','place','pl','highway','hwy','route',...
'free','wifi','delivery','pickup','order','online','call','phone','tel',...
'website','www','com'
};

brandBlocklist = lower(string(brandBlocklist));
brandBlocklist = unique(brandBlocklist);
brandBlocklist = unique(brandBlocklist);

%% =========================
% INIT
%% =========================
files = [];
for k = 1:numel(exts)
    files = [files; dir(fullfile(panoDir, exts(k)))];  
end
assert(~isempty(files), 'No panoramas found in: %s', panoDir);

easyocr = py.importlib.import_module('easyocr');
reader  = easyocr.Reader(py.list({'en','nl'}), pyargs('gpu', true));
np      = py.importlib.import_module('numpy');

N = numel(files);
Results = repmat(struct( ...
    'image',              "", ...
    'allTokens',          {{}}, ...
    'allConfs',           {{}}, ...
    'semanticLabel',      "", ...
    'semanticConfidence', 0,   ...
    'brandName',          "",  ...
    'matchedWords',       {{}}, ...
    'bboxes',             {{}} ...
), N, 1);

tStart = tic;

%% =========================
% MAIN LOOP
%% =========================
for p = 1:N
    imgPath = fullfile(panoDir, files(p).name);
    Results(p).image  = string(files(p).name);
    Results(p).bboxes = {zeros(0,4)};

   img = imread(imgPath);

% --- Resize large panoramas for CRAFT stability ---
maxDim = 4800; % safe size for GPU

[h,w,~] = size(img);
scale = maxDim / max(h,w);

if scale < 1
    img_small = imresize(img, scale);
else
    img_small = img;
end

% run CRAFT
bboxes = detectTextCRAFT(img_small);

% rescale boxes back to original coordinates
if scale < 1 && ~isempty(bboxes)
    bboxes(:,1:4) = bboxes(:,1:4) ./ scale;
end

    if isempty(bboxes)
        Results(p).semanticLabel = "NO_TEXT"; continue
    end

    keep   = (bboxes(:,3) >= minW) & (bboxes(:,4) >= minH);
    bboxes = bboxes(keep,:);
    % remove overlapping detections
if ~isempty(bboxes)
    scores = bboxes(:,3) .* bboxes(:,4);   % area as pseudo-score
bboxes = selectStrongestBbox(bboxes, scores, ...
    'OverlapThreshold',0.5);
end
    if isempty(bboxes)
        Results(p).semanticLabel = "NO_TEXT"; continue
    end

    if size(bboxes,1) > maxBoxesPerPano
        areas   = bboxes(:,3) .* bboxes(:,4);
        [~, si] = sort(areas, 'descend');
        bboxes  = bboxes(si(1:maxBoxesPerPano), :);
    end
    Results(p).bboxes = {bboxes};

    % ---- OCR every ROI ----
    allTokens    = strings(0);
    allConfs     = zeros(0,1);
    allTokensRaw = strings(0);   % preserve original casing for brand detection

    for i = 1:size(bboxes,1)
        roi = imcrop(img, bboxes(i,:));
        if isempty(roi), continue; end
        if roiScale ~= 1, roi = imresize(roi, roiScale); end

        if size(roi,3) == 3, roi_ocr = roi(:,:,[3 2 1]);
        else,                 roi_ocr = roi; end

       roi_np = np.array(roi_ocr);

out = reader.readtext(roi_np, pyargs('detail',1));

nOut = int64(py.len(out));

        for j = 1:nOut
 item = out{j};

% length of python list
nItem = int64(py.len(item));

% ---- TEXT ----
if nItem >= 2
    txt = string(item{2});
else
    txt = string(item{1});
end

% ---- CONFIDENCE ----
if nItem >= 3
    conf_py = item{3};
elseif nItem == 2
    conf_py = item{2};
else
    conf_py = py.float(0.5);
end

% safe conversion python → matlab
conf = str2double(string(conf_py));

if isnan(conf)
    conf = 0.5;
end
            if conf < minOcrConf, continue; end

            txtRaw = strtrim(txt);   % original casing
            txt    = lower(strtrim(txt));
            txt    = regexprep(txt, '[^a-zA-ZÀ-ÿ ]', '');
            txt    = strtrim(regexprep(txt, '\s+', ' '));

            if strlength(txt) > 2
                allTokens(end+1)     = txt;      
                allConfs(end+1,1)    = conf;     
                allTokensRaw(end+1)  = txtRaw;   
            end
        end
    end

    Results(p).allTokens = {cellstr(allTokens)};
    Results(p).allConfs  = {num2cell(allConfs)};

    if isempty(allTokens)
        Results(p).semanticLabel = "UNKNOWN"; continue
    end

   % ---- Classify ----
[bestLabel, bestScore, bestMatched] = classifyTokens(allTokens, allConfs, cats);

% ---- Extract brand name ----
brandName = extractBrand(allTokens, allConfs, allTokensRaw, cats, brandBlocklist);

% ---- Brand priority override ----
brandMap = containers.Map( ...
{'starbucks','decathlon','jumbo','rabobank'}, ...
{'RESTAURANT','SPORTS','SUPERMARKET','BANK'} );

brandKey = lower(strtrim(brandName));

if isKey(brandMap, brandKey)
    bestLabel = brandMap(brandKey);
    bestScore = bestScore + 3;
end
    % ---- Confidence ----
    if bestScore > 0
        semConf   = min(bestScore / 4, 1.0);
    else
        bestLabel = "UNKNOWN";
        semConf   = 0;
    end

    Results(p).semanticLabel      = bestLabel;
    Results(p).semanticConfidence = semConf;
    Results(p).brandName          = brandName;
    Results(p).matchedWords       = {cellstr(bestMatched)};

    % ---- Debug overlay (first pano only) ----
    if debugShowFirst && p == 1
        figure; imshow(img); hold on;
        for i = 1:size(bboxes,1)
            rectangle('Position', bboxes(i,:), 'EdgeColor','y', 'LineWidth', 2);
        end
        title(sprintf('%s | %s  brand="%s"  (%.2f)', ...
            files(p).name, bestLabel, brandName, semConf), 'Interpreter','none');
        fprintf('Tokens: '); disp(allTokens);
        fprintf('Matched: '); disp(bestMatched);
    end

    fprintf('[%d/%d] %s  →  %-15s  brand="%-20s"  conf=%.2f  tokens=%d\n', ...
        p, N, files(p).name, bestLabel, brandName, semConf, numel(allTokens));
end

elapsed = toc(tStart);
fprintf('\nDONE. %d panos in %.1f s (%.2f s/pano)\n', N, elapsed, elapsed/N);

%% =========================
% SUMMARY TABLE
%% =========================
images = string({Results.image})';
labels = string({Results.semanticLabel})';
brands = string({Results.brandName})';
conf   = [Results.semanticConfidence]';
T = table(images, labels, brands, conf, ...
    'VariableNames', {'Image','Label','Brand','Confidence'});
disp(T);

allL = unique(labels);
for i = 1:numel(allL)
    if allL(i)=="UNKNOWN" || allL(i)=="NO_TEXT", continue; end
    fprintf('\n=== %s ===\n', allL(i));
    disp(T(T.Label == allL(i), :));
end

%% =========================
% EXPORT JSON
%% =========================
jsonStruct = struct('image',{},'semanticLabel',{},'brandName',{}, ...
                    'semanticConfidence',{},'bboxes',{});
idx = 0;
for p = 1:N
    lbl = Results(p).semanticLabel;
    if lbl == "UNKNOWN" || lbl == "NO_TEXT", continue; end

    if isempty(Results(p).bboxes) || isempty(Results(p).bboxes{1})
        bboxMat = zeros(0,4);
    else
        bboxMat = Results(p).bboxes{1};
    end

    bboxCell = cell(size(bboxMat,1), 1);
    for i = 1:size(bboxMat,1)
        bboxCell{i} = bboxMat(i,:);
    end

    idx = idx + 1;
    jsonStruct(idx).image              = char(Results(p).image);
    jsonStruct(idx).semanticLabel      = char(lbl);
    jsonStruct(idx).brandName          = char(Results(p).brandName);
    jsonStruct(idx).semanticConfidence = Results(p).semanticConfidence;
    jsonStruct(idx).bboxes             = bboxCell;
end

outFile  = fullfile(panoDir, 'ocr_semantic_results.json');
jsonText = jsonencode(jsonStruct, 'PrettyPrint', true);
fid = fopen(outFile, 'w');
fprintf(fid, '%s', jsonText);
fclose(fid);
fprintf('\nJSON saved → %s  (%d detections)\n', outFile, idx);

end % main function

%% =========================================================
%  LOCAL FUNCTIONS
%% =========================================================

function cats = buildTaxonomy()
cats = struct();
cats.BEAUTY.strong = {
    'nail salon','nails','nail spa','spa','beauty salon'
};

cats.BEAUTY.weak = {
    'beauty','nails','spa'
};

cats.BEAUTY.minWordLen = 4;
cats.FLORIST.strong = {
    'florist','flower shop','flowers'
};

cats.FLORIST.weak = {
    'flowers','floral'
};

cats.FLORIST.minWordLen = 4;

cats.DRYCLEAN.strong = {
    'dry cleaners','dry cleaning','cleaners'
};

cats.DRYCLEAN.weak = {
    'cleaners','laundry'
};

cats.DRYCLEAN.minWordLen = 5;

cats.REALESTATE.strong = {
    'realty','real estate','realtor'
};

cats.REALESTATE.weak = {
    'realty','realtor'
};

cats.REALESTATE.minWordLen = 4;

cats.RESTAURANT.strong = {
    'restaurant','pizzeria','steakhouse','bbq','barbecue',...
    'taqueria','tacos','mexican','chinese','thai','japanese',...
    'sushi','italian','bistro','trattoria','osteria','diner',...
    'grill','grillhouse','burger','burger joint','pizza',...
    'sandwich shop','bagel shop','starbucks','coffee shop'
};

cats.RESTAURANT.weak = {
    'grill','pizza','pasta','burger','cafe','coffee','bakery',...
    'kitchen','diner','steak','sandwich','bar','eatery','tacos',...
    'bbq','bagel'
};

cats.RESTAURANT.minWordLen = 3;
cats.SUPERMARKET.strong = {
    'supermarket','grocery','groceries','food market',...
    'walmart','target','kroger','costco','whole foods',...
    'trader joe','safeway','publix','aldi','food lion'
};

cats.SUPERMARKET.weak = {
    'market','grocery','food','mart'
};

cats.SUPERMARKET.minWordLen = 4;
cats.CLOTHING.strong = {
    'fashion','clothing','apparel','boutique','menswear',...
    'womenswear','kidswear','outlet','fashion store'
};

cats.CLOTHING.weak = {
    'jeans','wear','style','clothes','fashion'
};

cats.CLOTHING.minWordLen = 4;
cats.SPORTS.strong = {
    'sportswear','sporting goods','sports shop',...
    'decathlon','dicks sporting goods'
};

cats.SPORTS.weak = {
    'sport','gym','fitness','running','outdoor'
};

cats.SPORTS.minWordLen = 4;
cats.SHOES.strong = {
    'footwear','sneakers','shoe store','boot shop'
};

cats.SHOES.weak = {
    'shoes','shoe','boots'
};

cats.SHOES.minWordLen = 4;
cats.PHARMACY.strong = {
    'pharmacy','drugstore','cvs','walgreens','rite aid'
};

cats.PHARMACY.weak = {
    'health','pharma','medical'
};

cats.PHARMACY.minWordLen = 5;

cats.BANK.strong = {
    'bank of america','wells fargo','chase','citibank','us bank'
};

cats.BANK.weak = {
    'bank','atm'
};

cats.BANK.minWordLen = 3;
cats.HAIRDRESSER.strong = {
    'hair salon','hairdresser','barbershop','barber shop'
};

cats.HAIRDRESSER.weak = {
    'hair','salon','barber'
};

cats.HAIRDRESSER.minWordLen = 4;
cats.RETAIL.strong = {
    'electronics','mobile','phone store','computer store',...
    'game store','gamestop','best buy'
};

cats.RETAIL.weak = {
    'store','shop','retail','phone'
};

cats.RETAIL.minWordLen = 4;
cats.FOODSHOP.strong = {
    'chocolate shop','candy store','sweet shop','gourmet foods'
};

cats.FOODSHOP.weak = {
    'chocolate','candy','sweets','food'
};

cats.FOODSHOP.minWordLen = 4;




end

% ---------------------------------------------------------

function [bestLabel, bestScore, bestMatched] = classifyTokens(allTokens, allConfs, cats)
catFields   = fieldnames(cats);
bestLabel   = "UNKNOWN";
bestScore   = 0;
bestMatched = strings(0);

for f = 1:numel(catFields)
    cname   = catFields{f};
    cdef    = cats.(cname);
    minLen  = cdef.minWordLen;
    score   = 0;
    matched = strings(0);

    for t = 1:numel(allTokens)
        token   = allTokens(t);
        tokConf = allConfs(t);
        words   = strsplit(token);
        if max(strlength(words)) < minLen, continue; end

        for kw = cdef.strong
            if wholeWordMatch(token, string(kw))
                score = score + 2;
                matched(end+1) = token;  
                break
            end
        end

        for kw = cdef.weak
            if wholeWordMatch(token, string(kw)) && tokConf >= 0.80
                score = score + 1;
                matched(end+1) = token;  
            end
        end
    end

    % Low-conf weak: only if keyword seen in 2+ distinct tokens
    for kw = cdef.weak
        kwStr  = string(kw);
        hitCnt = 0;
        for t = 1:numel(allTokens)
            if allConfs(t) < 0.80 && wholeWordMatch(allTokens(t), kwStr)
                hitCnt = hitCnt + 1;
            end
        end
        if hitCnt >= 2
            score = score + 1;
            matched(end+1) = kwStr;  
        end
    end

    if score > bestScore
        bestScore   = score;
        bestLabel   = string(cname);
        bestMatched = unique(matched);
    end
end
end

% ---------------------------------------------------------

function brandName = extractBrand(allTokens, allConfs, allTokensRaw, cats, blocklist)
% Extract the most likely brand/business name from OCR tokens.
%
% Strategy (in priority order):
%  1. Token appears in ALL-CAPS in original OCR text → strong brand signal
%  2. Token is Title-Case (first letter capital) → moderate brand signal
%  3. Token is not a keyword, not on blocklist, and length >= 5
%
% Among candidates, prefer highest-confidence token.
% Reject tokens that are purely generic words.

allKeywords = getAllKeywords(cats);

brandName    = "";
bestScore_b  = -1;
bestConf_b   = 0;
% Join adjacent tokens for multi-word brand candidates
joinedTokens = strings(0);
joinedConfs  = zeros(0,1);
joinedRaw    = strings(0);

for i = 1:numel(allTokens)-1
    joinedTokens(end+1) = allTokens(i) + " " + allTokens(i+1);
    joinedConfs(end+1)  = min(allConfs(i), allConfs(i+1));
    joinedRaw(end+1)    = allTokensRaw(i) + " " + allTokensRaw(i+1);
end

% Ensure column vectors for safe concatenation
allTokens    = allTokens(:);
allTokensRaw = allTokensRaw(:);
allConfs     = allConfs(:);

joinedTokens = joinedTokens(:);
joinedRaw    = joinedRaw(:);
joinedConfs  = joinedConfs(:);

allTokens    = [allTokens; joinedTokens];
allConfs     = [allConfs; joinedConfs];
allTokensRaw = [allTokensRaw; joinedRaw]; 
 

for t = 1:numel(allTokens)
    tok    = allTokens(t);       % lowercase cleaned
    tokRaw = strtrim(allTokensRaw(t)); % original casing
    cf     = allConfs(t);

    % Must be at least 5 chars
    if strlength(tok) < 5, continue; end

    % Skip keywords
    if ismember(tok, allKeywords), continue; end

    % Skip blocklist
    if ismember(tok, blocklist), continue; end

    % Skip tokens that contain only generic English/Dutch words
    % by checking every word against blocklist
    tokWords = strsplit(tok);
    % Remove generic suffix words
genericSuffix = {'mode','store','shop','winkel'};
tokWords = tokWords(~ismember(tokWords, genericSuffix));
tok = strjoin(tokWords,' ');
    allBlocked = all(cellfun(@(w) ismember(w, blocklist) || strlength(w) < 4, tokWords));
    if allBlocked, continue; end

    % Score based on casing of original token
    rawWords = strsplit(tokRaw);
    isAllCaps = all(cellfun(@(w) strcmp(w, upper(w)) && strlength(w) >= 3, rawWords));
    titleMask = cellfun(@(w) strlength(w)>=3 && strcmp(w(1), upper(w(1))), rawWords);
    isTitleCase = ~isAllCaps && any(titleMask);

    if isAllCaps
        capScore = 3;         % e.g. "DECATHLON", "JUMBO", "ALBERT HEIJN"
    elseif isTitleCase
        capScore = 2;         % e.g. "Decathlon", "Pasta Basta"
    else
        capScore = 1;         % lowercase — possible but less likely to be brand
    end

    % Prefer longer tokens, break ties by confidence, then capScore
    L = strlength(tok);
    combinedScore = capScore * 10 + L + cf;

    if combinedScore > bestScore_b || ...
       (combinedScore == bestScore_b && cf > bestConf_b)
        bestScore_b = combinedScore;
        bestConf_b  = cf;
        brandName   = tok;
    end
end
end

% ---------------------------------------------------------

function match = wholeWordMatch(sentence, keyword)
match = ~isempty(regexp(char(sentence), ...
    ['(?<![a-zA-ZÀ-ÿ])' regexptranslate('escape', char(keyword)) ...
     '(?![a-zA-ZÀ-ÿ])'], 'once'));
end

% ---------------------------------------------------------

function kwList = getAllKeywords(cats)
kwList = strings(0);
fields = fieldnames(cats);
for f = 1:numel(fields)
    kwList = [kwList, string(cats.(fields{f}).strong), ...
                      string(cats.(fields{f}).weak)];  
end
kwList = unique(kwList);
end