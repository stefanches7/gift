function icatb_postprocess_timecourses(param_file, varargin)
%% Write FNC and spectra information in *_postprocess_results.mat.
% FNC correlations (transformed to fisher z-scores) are saved as fnc_corrs_all with
% dimensions subjects x sessions x components x components. Spectra is
% saved as spectra_tc_all of dimensions subjects x sessions x spectral length.
%

%% Load defaults
icatb_defaults;
global EXPERIMENTAL_TR;
global TIMECOURSE_POSTPROCESS;
global DETRENDNUMBER;
global PARAMETER_INFO_MAT_FILE;
global GICA_RESULTS_SUMMARY;

compute_mi = 1;
compute_kurtosis = 1;
try
    compute_mi = GICA_RESULTS_SUMMARY.compute.mi;
    compute_kurtosis = GICA_RESULTS_SUMMARY.compute.kurtosis;
catch
end

for nV = 1:2:length(varargin)
    if (strcmpi(varargin{nV}, 'subjects'))
        subjects = varargin{nV + 1};
    elseif (strcmpi(varargin{nV}, 'components'))
        components = varargin{nV + 1};
    elseif (strcmpi(varargin{nV}, 'outputDir'))
        resultsDir = varargin{nV + 1};
    elseif (strcmpi(varargin{nV}, 'compute_mi'))
        compute_mi = varargin{nV + 1};
    elseif (strcmpi(varargin{nV}, 'compute_kurtosis'))
        compute_kurtosis = varargin{nV + 1};
    end
end

filterP = ['*', PARAMETER_INFO_MAT_FILE, '*.mat'];
if (~exist('param_file', 'var'))
    param_file = icatb_selectEntry('typeEntity', 'file', 'title', 'Select Parameter File', 'filter', filterP);
    drawnow;
end

if (isempty(param_file))
    error('ICA parameter file is not selected');
end

if (ischar(param_file))
    load(param_file);
    
    if ~exist('sesInfo', 'var')
        error('Not a valid parameter file');
    end
    outputDir = fileparts(param_file);
else
    sesInfo = param_file;
    outputDir = sesInfo.outputDir;
end

if (isempty(outputDir))
    outputDir = pwd;
end

if (~exist('resultsDir', 'var') || isempty(resultsDir))
    resultsDir = outputDir;
end

try
    modalityType = sesInfo.modality;
catch
    modalityType = icatb_get_modality;
end

if (~strcmpi(modalityType, 'fmri'))
    warning('!!!Timecourse post-processing will be done only for fMRI modality');
    return;
end

writeInfo = 0;
try
    writeInfo = TIMECOURSE_POSTPROCESS.write;
catch
end

if (~writeInfo)
    return;
end

if (isfield(sesInfo, 'TR'))
    TR = sesInfo.TR;
else
    if (isempty(EXPERIMENTAL_TR))
        warning('!!!Experimental TR variable (EXPERIMENTAL_TR) in seconds is missing.');
        return;
    end
    TR = EXPERIMENTAL_TR;
end

if (length(TR) == 1)
    TR = repmat(TR, 1, sesInfo.numOfSub);
else
    if (length(TR) ~= sesInfo.numOfSub)
        error('Length of TR must match the number of subjects');
    end
end

if (~exist('subjects', 'var'))
    subjects = (1:sesInfo.numOfSub);
end

subjects (subjects > max(sesInfo.numOfSub)) = [];

if (isempty(subjects))
    error('Please check the subjects variable passed');
end


if (~exist('components', 'var'))
    components = (1:sesInfo.numComp);
end

components (components > max(sesInfo.numComp)) = [];

if (isempty(components))
    error('Please check the components variable passed');
end

% Spectra info
tapers = [3, 5];
sampling_frequency = 1/min(TR);
frequency_band = [0, 1/(2*min(TR))];

% FNC (despike timecourses and High freq cutoff in Hz)
despike_tc = 1;
cutoff_frequency = 0.15;

save_tc = 0;
try
    save_tc = TIMECOURSE_POSTPROCESS.save_timecourses;
catch
end

%% Write results
if (writeInfo)
    
    % SEPCTRA PARAMS (tapers, sampling_freq, frequency_band)
    try
        tapers = TIMECOURSE_POSTPROCESS.spectra.tapers;
    catch
    end
    
    %     try
    %         sampling_frequency = TIMECOURSE_POSTPROCESS.spectra.sampling_frequency;
    %     catch
    %     end
    %
    %     try
    %         frequency_band = TIMECOURSE_POSTPROCESS.spectra.frequency_band;
    %     catch
    %     end
    
    % FNC PARAMs (Despike timecourses and high frequency cutoff in Hz)
    try
        despike_tc = TIMECOURSE_POSTPROCESS.fnc.despike_tc;
    catch
    end
    
    try
        cutoff_frequency = TIMECOURSE_POSTPROCESS.fnc.cutoff_frequency;
    catch
    end
    
    outputFile = fullfile(resultsDir, [sesInfo.userInput.prefix, '_postprocess_results.mat']);
    
    %% Uncompress files
    subjectICAFiles = icatb_parseOutputFiles('icaOutputFiles', sesInfo.icaOutputFiles, 'numOfSub', sesInfo.numOfSub, 'numOfSess', sesInfo.numOfSess, 'flagTimePoints', ...
        sesInfo.flagTimePoints);
    sesInfo.outputDir = outputDir;
    fileIn = dir(fullfile(outputDir, [sesInfo.calibrate_components_mat_file, '*.mat']));
    filesToDelete = {};
    if (length(fileIn) ~= sesInfo.numOfSub*sesInfo.numOfSess)
        disp('Uncompressing subject component files ...');
        filesToDelete = icatb_unZipSubjectMaps(sesInfo, subjectICAFiles);
    end
    
    %% Spectra
    spectra_params = struct('tapers', tapers, 'Fs', sampling_frequency, 'fpass', frequency_band);
    countS = 0;
    fprintf('\nComputing spectra and FNC correlations of all subjects and sessions components ...\n');
    if (despike_tc)
        disp('Timecourses will be despiked when computing FNC correlations...');
    end
    
    if (min(cutoff_frequency) > 0)
        disp(['Timecourses will be filtered when computing FNC correlations using HF cutoff of ', num2str(cutoff_frequency), ' Hz ...']);
    end
    
    minTpLength = min(sesInfo.diffTimePoints);
    if (~all(TR == min(TR)))
        tmpTR = TR;
        tmpTR = repmat(tmpTR(:)', sesInfo.numOfSess, 1);
        tmpTR = tmpTR(:)';
        ratiosTR = (tmpTR(:)')./min(tmpTR);
        [numN, denN] = rat(ratiosTR);
        chkTp = ceil((sesInfo.diffTimePoints(:)'.*numN)./denN);
        minTpLength = min(chkTp);
    end
    
    if (exist(outputFile, 'file'))
        try
            delete (outputFile);
        catch
            error([outputFile, ' is not cleaned up prior to new analysis. Delete file manually']);
        end
    end
    
    matFileInfo = matfile(outputFile, 'Writable', true);
    matFileInfo.subjects = subjects;
    matFileInfo.components = components;
    
    for nSub = 1:length(subjects)
        for nSess = 1:sesInfo.numOfSess
            countS = countS + 1;
            timecourses = icatb_loadComp(sesInfo, components, 'subjects', subjects(nSub), 'sessions', nSess, 'vars_to_load', 'tc', ...
                'detrend_no', DETRENDNUMBER, 'subject_ica_files', subjectICAFiles);
            
            if (compute_kurtosis)
                kvals = kurt(timecourses);
                kvals = reshape(kvals, 1, 1, length(kvals));
                if (~isempty(who(matFileInfo, 'kurt_tc')))
                    matFileInfo.kurt_tc(nSub, nSess, :) = kvals;
                else
                    matFileInfo.kurt_tc = kvals;
                end
            end
            
            % Interpolate timecourses if needed for variable TRs across
            % subjects
            if (~all(TR == min(TR)))
                interpFactor = TR(subjects(nSub))/min(TR);
                [num, denom] = rat(interpFactor);
                timecourses = resample(timecourses, num, denom);
            end
            
            %timecourses = timecourses(1:min(sesInfo.diffTimePoints), :);
            [temp_spectra, freq] = icatb_get_spectra(timecourses(1:minTpLength, :)', min(TR), spectra_params);
            temp_spectra = temp_spectra./repmat(sum(temp_spectra, 2), [1, size(temp_spectra, 2)]);
            temp_spectra = temp_spectra';
            
            temp_spectra = reshape(temp_spectra, 1, 1, size(temp_spectra, 1), size(temp_spectra, 2));
            
            if (~isempty(who(matFileInfo, 'spectra_tc_all')))
                matFileInfo.spectra_tc_all(nSub, nSess, :, :) = temp_spectra;
            else
                matFileInfo.spectra_tc_all = temp_spectra;
            end
            
            % despike
            if (despike_tc)
                timecourses = icatb_despike_tc(timecourses, min(TR));
            end
            
            % Filter
            if (min(cutoff_frequency) > 0)
                timecourses = icatb_filt_data(timecourses, min(TR), cutoff_frequency);
            end
            
            c = icatb_corr(timecourses);
            c(1:size(c, 1) + 1:end) = 0;
            c = icatb_r_to_z(c);
            
            c = reshape(c, 1, 1, size(c, 1), size(c, 2));
            
            if (~isempty(who(matFileInfo, 'fnc_corrs_all')))
                matFileInfo.fnc_corrs_all(nSub, nSess, :, :) = c;
            else
                matFileInfo.fnc_corrs_all = c;
            end
            
            % save timecourses if needed
            if (save_tc)
                outfile = ['cleaned_', deblank(subjectICAFiles(nSub).ses(nSess).name(1, :))];
                saveTimecourses(outfile, timecourses, sesInfo.HInfo, outputDir);
            end
            
        end
    end
    
    % mutual information between components
    countS = 0;
    fprintf('\n');
    
    if (compute_kurtosis || compute_mi)
        
        for nSub = 1:length(subjects)
            for nSess = 1:sesInfo.numOfSess
                countS = countS + 1;
                ic = icatb_loadComp(sesInfo, components, 'subjects', subjects(nSub), 'sessions', nSess, 'vars_to_load', 'ic', 'subject_ica_files', ...
                    subjectICAFiles);
                
                if (compute_kurtosis)
                    kvals = kurt(ic);
                    kvals = reshape(kvals, 1, 1, length(kvals));
                    
                    if (~isempty(who(matFileInfo, 'kurt_ic')))
                        matFileInfo.kurt_ic(nSub, nSess, :) = kvals;
                    else
                        matFileInfo.kurt_ic = kvals;
                    end
                end
                
                if (compute_mi)
                    
                    tmp = icatb_compute_mi(ic');
                    
                    tmp = reshape(tmp, 1, 1, size(tmp, 1), size(tmp, 2));
                    
                    if (~isempty(who(matFileInfo, 'spatial_maps_MI')))
                        matFileInfo.spatial_maps_MI(nSub, nSess, :, :) = tmp;
                    else
                        matFileInfo.spatial_maps_MI = tmp;
                    end
                    
                end
                clear tmp;
            end
        end
        
    end
    
    
    if (compute_kurtosis)
        matFileInfo.kurt_comp = struct('tc', matFileInfo.kurt_tc, 'ic', matFileInfo.kurt_ic);
        matFileInfo.kurt_ic = [];
        matFileInfo.kurt_tc = [];
    end
    
    if (length(subjects)*sesInfo.numOfSess == 1)
        
        matFileInfo.spectra_tc_all = squeeze(matFileInfo.spectra_tc_all);
        matFileInfo.fnc_corrs_all = squeeze(matFileInfo.fnc_corrs_all);
        if (~isempty(who(matFileInfo, 'spatial_maps_MI')))
            matFileInfo.spatial_maps_MI = squeeze(matFileInfo.spatial_maps_MI);
        end
        
        if (~isempty(who(matFileInfo, 'kurt_comp')))
            tmp = matFileInfo.kurt_comp;
            tmp.ic = reshape(tmp.ic, 1, length(components));
            tmp.tc = reshape(tmp.tc, 1, length(components));
            matFileInfo.kurt_comp = struct('ic', squeeze(tmp.ic), 'tc', squeeze(tmp.tc));
        end
        
    end
    
    matFileInfo.freq = freq;
    
    fprintf('Done\n\n');
    disp(['File ', outputFile, ' contains spectra and FNC correlations']);
    disp('spectra_tc_all - Timecourses spectra. spectra_tc_all variable is of dimensions subjects x sessions x spectral length x components');
    disp('fnc_corrs_all - FNC correlations transformed to fisher z-scores. fnc_corrs_all variable is of dimensions subjects x sessions x components x components');
    if (compute_mi)
        disp('spatial_maps_MI - Mutual information is computed between components spatially. spatial_maps_MI variable is of dimensions subjects x sessions x components x components');
    end
    if (compute_kurtosis)
        disp('kurt_comp - Kurtosis is computed on the spatial maps and timecourses. kurt_comp variable is of dimensions subjects x sessions x components');
    end
    
    if (exist('filesToDelete', 'var') && ~isempty(filesToDelete))
        icatb_cleanupFiles(filesToDelete, outputDir);
    end
    
end



function k = kurt(x)
% Kurtosis

x = icatb_remove_mean(x);
s2 = mean(x.^2);
m4 = mean(x.^4);
k = (m4 ./ (s2.^2));




function saveTimecourses(outfile, A, HInfo, outputDir)


icatb_defaults;
global COMPONENT_NAMING;
global TIMECOURSE_NAMING;
global FUNCTIONAL_DATA_FILTER;
global ZIP_IMAGE_FILES;
[pp, bb, fileExtn] = fileparts(FUNCTIONAL_DATA_FILTER);

zipFiles = ZIP_IMAGE_FILES;

%determine output file names
lastUnderScore = icatb_findstr(outfile,'_');
lastUnderScore = lastUnderScore(end);
component_name = outfile(1:lastUnderScore);

%timecourse dimensions
tc_dim = [size(A, 1), size(A, 2), 1];
%components dim, e.g. dimensions of image
c_dim = [HInfo.DIM(1),HInfo.DIM(2),HInfo.DIM(3)];

% Check the data type and if complex add R and I namings for the real part
% and imaginary part

%write timecourses in analyze format(1 file)
V = HInfo.V(1);
V.dim(1:3) = [tc_dim(1) tc_dim(2) 1];
V.dt(1) = 4;
V.n(1) = 1;

timecourse_name = strrep(component_name, COMPONENT_NAMING, TIMECOURSE_NAMING);


V.fname = [timecourse_name, fileExtn];

zipFileName = {};
if strcmpi(zipFiles, 'yes')
    % zip file name
    zipFileName = [component_name, '.zip'];
end

files_to_zip = {};

% return zip files
files_to_zip = returnZipFiles(V.fname, fileExtn, files_to_zip, zipFiles);

V.fname = fullfile(outputDir, V.fname);

% write the images
icatb_write_vol(V, A);


% zip files
if (~isempty(zipFileName))
    [p, fN, extn] = fileparts(zipFileName);
    outputDir = fullfile(outputDir, p);
    zipFileName2 = [fN, extn];
    files_to_zip2 = regexprep(files_to_zip, ['.*\', filesep], '');
    icatb_zip(zipFileName2, files_to_zip2, outputDir);
    if (deleteFiles)
        % delete the files
        icatb_delete_file_pattern(char(files_to_zip2), outputDir);
    end
end
% end for checking


function files_to_zip = returnZipFiles(newFile, fileExtn, files_to_zip, zipFiles)

if ~exist('files_to_zip', 'var')
    files_to_zip = {};
end

if strcmpi(zipFiles, 'yes')
    countZip = length(files_to_zip) + 1;
    % for analyze zip header files also
    if strcmpi(fileExtn, '.img')
        files_to_zip{countZip} = [newFile];
        countZip = length(files_to_zip) + 1;
        files_to_zip{countZip} = [newFile(1:end-3), 'hdr'];
    else
        files_to_zip{countZip} = [newFile];
    end
    
end

