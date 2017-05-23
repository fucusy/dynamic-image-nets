function [net, info] = cnn_dicnn(varargin)
%CNN_DICNN Demonstrates fine-tuning a pre-trained CNN on UCF101 dataset

path = fullfile(fileparts(mfilename('fullpath')), ...
'..', 'matconvnet', 'matlab');
fprintf('add search path:%s\n', path);
addpath(path);


path = fullfile(fileparts(mfilename('fullpath')), ...
'..', 'matconvnet', 'examples');
fprintf('add search path:%s\n', path);
addpath(path);

path = fullfile(fileparts(mfilename('fullpath')), ...
'..', 'matconvnet', 'examples', 'imagenet');
fprintf('add search path:%s\n', path);
addpath(path);



run(fullfile(fileparts(mfilename('fullpath')), ...
  '..', 'matconvnet', 'matlab', 'vl_setupnn.m')) ;

addpath Layers Datasets

data_path='/Volumes/Passport/data/';
data_id='caisa_dataset_b';

opts.dataDir = fullfile(data_path,data_id);
opts.expDir  = fullfile(opts.dataDir, 'exp') ;
opts.modelPath = fullfile(data_path, 'UCF101/models','imagenet-caffe-ref.mat');

[opts, varargin] = vl_argparse(opts, varargin) ;

opts.numFetchThreads = 8 ;

opts.lite = false ;
opts.imdbPath = fullfile(opts.expDir, 'imdb.mat');
opts.ARPoolLayer = 'conv0'; % before conv1

opts.split = 1; % data split
opts.reverseDyn = 0; % reverse video frames e.g.[N:-1:1]
opts.train = struct() ;
opts.train.gpus = [];
opts.train.batchSize = 	 8;
opts.train.numSubBatches = 4;
opts.train.learningRate = 1e-4 * [ones(1,15), 0.1*ones(1,5)];

opts = vl_argparse(opts, varargin) ;
if ~isfield(opts.train, 'gpus'), opts.train.gpus = []; end;

% -------------------------------------------------------------------------
%                                                             Prepare model
% -------------------------------------------------------------------------
net = load(opts.modelPath);
net = cnn_dicnn_init(net,opts);
% -------------------------------------------------------------------------
%                                                              Prepare data
% -------------------------------------------------------------------------

if exist(opts.imdbPath,'file')
  imdb = load(opts.imdbPath) ;
else
  imdb = cnn_casia_b_setup_data('dataDir', opts.dataDir, 'lite', opts.lite) ;
  mkdir(opts.expDir) ;
  save(opts.imdbPath, '-struct', 'imdb') ;
end

% UCF101 has 3 data splits
if opts.split>3
  error('split should be <=3');
end
imdb.images.set = imdb.images.sets(opts.split,:);

% reverse frame order
if opts.reverseDyn
  for i=1:numel(imdb.images.names)
    imdb.images.names{i} = imdb.images.names{i}(end:-1:1);
  end
end

% Set the class names in the network
net.meta.classes.name = imdb.classes.name ;
net.meta.classes.description = imdb.classes.name ;

% -------------------------------------------------------------------------
%                                                                     Learn
% -------------------------------------------------------------------------
opts.train.train = find(imdb.images.set==1) ;
opts.train.val = find(imdb.images.set==3) ;

[net, info] = cnn_train_dag(net, imdb, getBatchFn(opts, net.meta), ...
                      'expDir', opts.expDir, ...
                      opts.train) ;

% -------------------------------------------------------------------------
%                                                                    Deploy
% -------------------------------------------------------------------------

net = cnn_imagenet_deploy(net) ;
modelPath = fullfile(opts.expDir, 'net-deployed.mat');

net_ = net.saveobj() ;
save(modelPath, '-struct', 'net_') ;
clear net_ ;

% -------------------------------------------------------------------------
function fn = getBatchFn(opts, meta)
% -------------------------------------------------------------------------
useGpu = numel(opts.train.gpus) > 0 ;

bopts.numThreads = opts.numFetchThreads ;
bopts.imageSize = meta.normalization.imageSize ;
bopts.border = meta.normalization.border ;
% bopts.averageImage = []; 
bopts.averageImage = meta.normalization.averageImage ;
% bopts.rgbVariance = meta.augmentation.rgbVariance ;
% bopts.transformation = meta.augmentation.transformation ;


fn = @(x,y) getDagNNBatch(bopts,useGpu,x,y) ;



% -------------------------------------------------------------------------
function inputs = getDagNNBatch(opts, useGpu, imdb, batch)
% -------------------------------------------------------------------------

% batch refers to videos (not for frames)
if isempty(batch)
  inputs = {'input', [], 'label', [], 'VideoId1', [], 'VideoId2', []};
  return;
end

isVal = ~isempty(batch) && imdb.images.set(batch(1)) ~= 1 ;

if ~isVal, transformation='stretch'; else transformation='none';end

names = imdb.images.names(batch);


% images = strcat([imdb.imageDir filesep], imdb.images.name(batch)) ;

namesM = {};
nVids = numel(batch);

VideoId1 = [];
VideoId2 = [];

% step-size
stepSize = 6;
% pool nFrames into a dynamic image
nFrames = 10;

% number of dynamic images to be max pooled later
% using less nDynImgs leads to a faster training and less overfitting
if isVal
  nDynImgs = 5;
else
  nDynImgs = 10;
end


c1 = 1;
for v=1:nVids
  
  name = names{v};
  nFrms = numel(name);

  nSample = nFrames;
  nr = numel(1:stepSize:nFrms);
  
  % jitter by removing 75 % and limit a batch to nMaxs * nSamples images
  if nr > 1 && (~isVal || nr>nDynImgs)
    rat = min(nDynImgs,ceil(0.75*nr));
    ri = randperm(nr);
    ri = ri(1:rat);
    r = zeros(1,nr);
    r(ri) = 1;
  else
    r = ones(1,nr);
  end
  
  c3 = 1;
  c2 = 0;
  
  for f=1:stepSize:nFrms
    if r(c3)
      idx = f:min(f+nSample-1,nFrms) ;
      namesM{end+1} = name(idx);
      VideoId1 = [VideoId1 c1 * ones(1,numel(idx))];
      c1 = c1 + 1;
      c2 = c2 + 1;
    end
    c3 = c3 + 1;
  end
  VideoId2 = [VideoId2 v * ones(1,c2) ] ;
end

images = strcat([imdb.imageDir filesep], horzcat(namesM{:}) ) ;

im = cnn_video_get_batch(images, VideoId1, opts, ...
  'transformation', transformation, 'prefetch', nargout == 0, ...
  'subMean', false) ;

if nargout > 0
  if useGpu
    im = gpuArray(im) ;
  end
  inputs = {'input', im, 'label', imdb.images.label(batch), ...
    'VideoId1', VideoId1, 'VideoId2', VideoId2};
end
