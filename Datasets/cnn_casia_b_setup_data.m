function imdb = cnn_ucf101_setup_data(varargin)
% CNN_UCF101_SETUP_DATA Initialize UCF101 - Action Recognition Data Set
% http://crcv.ucf.edu/data/UCF101.php
% this script requires UCF101 downloaded and frames extracted in frames
% folder

path = fullfile(fileparts(mfilename('fullpath')), ...
'../matconvnet', 'matlab');
fprintf('add search path:%s\n', path);
addpath(path);

vl_setupnn()


opts.dataDir=fullfile('/Volumes/Passport/data/caisa_dataset_b');
opts.lite = false ;
opts = vl_argparse(opts, varargin) ;

%% ------------------------------------------------------------------------
%                                                  Load categories metadata
% -------------------------------------------------------------------------


cats = cell(1, 101);
for i=1:numel(cats)
  cats{i} = sprintf('%03d', i);
end

imdb.classes.name = cats ;
imdb.imageDir = fullfile(opts.dataDir, 'frames') ;

%% ------------------------------------------------------------------------
%                                              load image names and labels
% -------------------------------------------------------------------------

fprintf('searching training images ...\n') ;
names = {} ;
name = {};
labels = {} ;
for d = dir(fullfile(imdb.imageDir, '*090'))'
  id = lower(d.name(1:3));
  [~,lab] = ismember(id, lower(cats)) ;
  if lab==0	
    display(sprintf('no class label found for %s, continue',d.name));
	continue;
  end
  ims = dir(fullfile(imdb.imageDir, d.name, '*.png')) ;
  name{end+1} = d.name;
  names{end+1} = strcat([d.name, filesep], {ims.name}) ;
  labels{end+1} = lab ;
  if mod(numel(names), 10) == 0, fprintf('.') ; end
  if mod(numel(names), 500) == 0, fprintf('\n') ; end
  %fprintf('found %s with %d images\n', d.name, numel(ims)) ;
end
% names = horzcat(names{:}) ;
labels = horzcat(labels{:}) ;

imdb.images.id = 1:numel(names) ;
imdb.images.name = name ;
imdb.images.names = names ;
imdb.images.label = labels ;


%% ------------------------------------------------------------------------
%                                                 load train / test splits
% -------------------------------------------------------------------------

fprintf('labeling data...(this may take couple of minutes)') ;
imdb.images.sets = zeros(3, numel(names)) ;
setNames = {'train','test'};
setVal = [1,3];

for s=1:numel(setNames)
  for i=1:1
    trainFl = fullfile(opts.dataDir, 'ucfTrainTestlist',sprintf('%slist%02d.txt',...
      setNames{s},i)) ;
    trainList = importdata(trainFl);
    if isfield(trainList,'textdata')
      trainList = trainList.textdata;
    end
    for j=1:numel(trainList)
      tmp = trainList{j};
      [~,lab] = ismember(lower(tmp), lower(name)) ;
      if lab==0		
        display(sprintf('cannot find the video %s in, continue',tmp));
        continue;
      end
%       if trainList.data(j) ~= labels(lab)
%         error('Labels do not match for %s',tmp{2});
%       end
      imdb.images.sets(i,lab) = setVal(s);
    end
  end  
end
fprintf('\n') ;
%% ------------------------------------------------------------------------
%                                                            Postprocessing
% -------------------------------------------------------------------------

% sort categories by WNID (to be compatible with other implementations)
[imdb.classes.name,perm] = sort(imdb.classes.name) ;
relabel(perm) = 1:numel(imdb.classes.name) ;
ok = imdb.images.label >  0 ;
imdb.images.label(ok) = relabel(imdb.images.label(ok)) ;

if opts.lite
  % pick a small number of images for the first 10 classes
  % this cannot be done for test as we do not have test labels
  clear keep ;
  for i=1:10
    sel = find(imdb.images.label == i) ;
    train = sel(imdb.images.sets(1,sel) == 1) ;
    test = sel(imdb.images.sets(1,sel) == 3) ;
    keep{i} = [train test] ;
  end
  keep = keep{:};
  imdb.images.id = imdb.images.id(keep) ;
  imdb.images.name = imdb.images.name(keep) ;
  imdb.images.names = imdb.images.names(keep) ;
  imdb.images.sets = imdb.images.sets(1,keep) ;
  imdb.images.label = imdb.images.label(keep) ;
end
