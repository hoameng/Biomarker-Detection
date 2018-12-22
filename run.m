
addpath(genpath('../ieeg-matlab-1.13.2'));
%addpath('~/gdriveshort/Libraries/Utilities/hline_vline');
addpath(genpath('../portal-matlab-tools/Analysis'))
addpath(genpath('../portal-matlab-tools/Utilities'))
%javaaddpath('Z:\public\USERS\hoameng/Libraries/ieeg-matlab-1.13.2/IEEGToolbox/lib/ieeg-matlab.jar');

params = initialize_task;

% Load data
session = loadData(params);
% 
% GENERATE TABLE
%find length of each dataset
subj = cell(numel(session.data),1);
dR = zeros(numel(session.data),1);
for i = 1:numel(session.data)
    subj{i} = session.data(i).snapName;
    dR(i) = session.data(i).rawChannels(1).get_tsdetails.getDuration/1e6/60/60/24;
end

channelIdxs = cell(numel(session.data),1);
for i = 1:numel(session.data)
    channelIdxs{i} = [1 3];
end

% groupChannels = {
%     {'EEG EEG1.1A-B','EEG EEG2.1A-B','EMG EMG.1'},  
%     {'EEG EEG1.2A-B','EEG EEG2.2A-B','EMG EMG.2'},
%     %{'EEG EEG1.3A-B','EEG EEG2.3A-B','EMG EMG.3'}, %not used
%     {'EEG EEG1A-B','EEG EEG2A-B','EMG EMG'},
%     };

groupChannels = {
    {'EEG EEG1.1A-B','EEG EEG2.1A-B'},  
    {'EEG EEG1.2A-B','EEG EEG2.2A-B'},
    %{'EEG EEG1.3A-B','EEG EEG2.3A-B','EMG EMG.3'}, %not used
    {'EEG EEG1A-B','EEG EEG2A-B'},
    };

%anonymous functions
%EnergyFn = @(x) mean(x.^2);
%ZCFn = @(x) sum((x(1:end-1,:)>repmat(mean(x),size(x,1)-1,1)) & x(2:end,:)<repmat(mean(x),size(x,1)-1,1) | (x(1:end-1,:)<repmat(mean(x),size(x,1)-1,1) & x(2:end,:)>repmat(mean(x),size(x,1)-1,1)));
LLFn = @(x,fs) nanmean(abs(diff(x)));

% PARAMETERS
feature='LL';
indivMode = 1;
globalMode = 1;
winLen = 2;
winDisp = 1;
switch feature
    case 'freq'
        featFn = @calc_featureswithfreqcorr;
        prefix = 'freq';
    case 'LL'
        featFn = LLFn;
        prefix = 'LL';
end
        

%% split layer based on channels
%[~,splitTimes,splitCh] = split_annotations(allEvents, timesUSec, eventChannels);


%% Train Model
% for each dataset
f_X = [];
f_Y = [];
for i = 1:numel(session.data)
    fprintf('Working on %s\n',session.data(i).snapName);
    feat = [];
    feat2 = [];
    fs = session.data(i).sampleRate;
    channels = session.data(i).channelLabels(:,1);
    layer_names = {session.data(i).annLayer.name};
    layer = layer_names(ismember(layer_names,'True_Seizures'));
    %if layer exists
    if ~isempty(layer)
        [feat, ch] = extractFeaturesFromAnnotationLayer(session.data(i),layer{1},winLen,winDisp,fs,featFn);
    end
    layer = layer_names(ismember(layer_names,'Non_Seizures'));
    %if layer exists
    if ~isempty(layer)
        [feat2, ch2] = extractFeaturesFromAnnotationLayer(session.data(i),layer{1},winLen,winDisp,fs,featFn);
    end
    
    if ~isempty(feat) && ~isempty(feat2)
        %train model
        feat = cell2mat(feat);
        feat2 =cell2mat(feat2);
        X = [feat; feat2];
        Y = [ones(size(feat,1),1); zeros(size(feat2,1),1)];
        f_X = [f_X;X];
        f_Y = [f_Y;Y];
        
        if indivMode==1
            c = [0 50; 1 0];
            model = fitcsvm(X,Y,'KernelFunction','linear','Cost',c);
            %lr = mnrfit(X,categorical(Y+1))
            %cv = crossval(model);
            %kfoldLoss(cv)
            %% detect for current dataset
            run_detections(session.data(i),model,winLen,winDisp,ch{1},featFn,strcat(prefix,'-indiv'),'append')
        end
    else
        fprintf('No Annotations\n');
    end
end
% model = TreeBagger(100,X,Y);
c = [0 50; 1 0];
model = fitcsvm(f_X,f_Y,'KernelFunction','linear','Cost',c);
%lr = mnrfit(X,categorical(Y+1))
cv = crossval(model);
kfoldLoss(cv)
%% detect for current dataset
for i = 1:numel(session.data)
    channels = session.data(i).channelLabels(:,1);
    %run through each mouse combination
    if globalMode==1
        for j = 1:numel(groupChannels)
            curCh = groupChannels{j};
            ch = find(ismember(channels,curCh));
            run_detections(session.data(i),model,winLen,winDisp,ch,featFn,strcat(prefix,'-global'),'append')
        end
    end
end

%%
% Input: timesUsec, eventChannels
% output: cell array of timesUsec, eventChannels that correspond to
% unique channels
function [splitEvents, splitTimes, splitCh] = split_annotations(events,times,channels)   
    C =channels;
    maxLengthCell=max(cellfun('size',C,2));  %finding the longest vector in the cell array
    for i=1:length(C)
        for j=cellfun('size',C(i),2)+1:maxLengthCell
             C{i}(j)=0;   %zeropad the elements in each cell array with a length shorter than the maxlength
        end
    end
    A=cell2mat(C); %A is your matrix
    [~,~,IC] = unique(A,'rows','sorted');
    splitEvents = cell(1,max(IC));
    splitTimes = cell(1,max(IC));
    splitCh = cell(1,max(IC));
    for i=1:max(IC)
        splitEvents{i} = events(IC==i);
        splitTimes{i} = times(IC==i,:);
        tmp = cell2mat(channels(IC==i));
        splitCh{i} = tmp(1,:);
    end
end



