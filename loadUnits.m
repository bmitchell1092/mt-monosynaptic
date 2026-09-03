function [units, session, events] = loadUnits(varargin)
% loadUnits   Load the Katniss MT unit set, optionally restricted to an epoch or filtered.
%
% PURPOSE
% -------
% One call to get spike times and unit metadata. The data file is already curated -- the
% spike sorter's clusters have been resolved into units -- so there is nothing to clean up
% before you start.
%
% INPUTS (all optional, name/value)
% ---------------------------------
%   'File'        path to the .mat  (default: data/katniss_251120_units.mat)
%   'Epoch'       'all' (default) | 'task' | 'spontaneous' | [t0 t1] in seconds
%                    Spike times are cut to the window. They keep ABSOLUTE times, so they
%                    still line up with events.times_s.
%   'MinSpikes'   keep units with at least this many spikes IN THE EPOCH (default 0)
%   'MaxPctRefr'  keep units whose refractory violation rate is below this (default Inf)
%
% OUTPUTS
% -------
%   units     1 x nUnits struct array — see README for every field
%   session   recording metadata, including session.epochs
%   events    behavioural event times and codes, on the same clock as the spikes
%
% EXAMPLES
% --------
%   units = loadUnits;                                       % everything
%   units = loadUnits('Epoch', 'task', 'MinSpikes', 1000);   % task epoch, well-sampled units
%   [units, session, events] = loadUnits('Epoch', 'spontaneous');
%
% See also: plotEvokedSpikes

p = inputParser;
p.addParameter('File', '', @(x) ischar(x) || isstring(x));
p.addParameter('Epoch', 'all');
p.addParameter('MinSpikes', 0, @isnumeric);
p.addParameter('MaxPctRefr', Inf, @isnumeric);
p.parse(varargin{:});
opt = p.Results;

f = char(opt.File);
if isempty(f)
    f = fullfile(fileparts(mfilename('fullpath')), 'data', 'katniss_251120_units.mat');
end
if ~isfile(f)
    error('loadUnits:noFile', ['\nData file not found:\n  %s\n\n' ...
        'The data is not stored in this repository -- it is 235 MB, over GitHub''s\n' ...
        'per-file limit. Download katniss_251120_units.mat using the link in the\n' ...
        '"Getting the data" section of the README, and put it in the data/ folder\n' ...
        'next to loadUnits.m. Or pass a path directly:\n\n' ...
        '    loadUnits(''File'', ''C:\\path\\to\\katniss_251120_units.mat'')\n'], f);
end

S = load(f);
units = S.units;
session = S.session;
events = S.events;

% ---- resolve the epoch window ----
if isnumeric(opt.Epoch)
    if numel(opt.Epoch) ~= 2 || opt.Epoch(2) <= opt.Epoch(1)
        error('loadUnits:badEpoch', 'Numeric Epoch must be [t0 t1] with t1 > t0.');
    end
    win = double(opt.Epoch(:)');
    epochName = 'custom';
else
    epochName = lower(char(opt.Epoch));
    switch epochName
        case 'all',         win = [0, session.duration_s];
        case 'task',        win = session.epochs.task;
        case 'spontaneous', win = session.epochs.spontaneous;
        otherwise
            error('loadUnits:badEpoch', ...
                'Epoch must be ''all'', ''task'', ''spontaneous'', or [t0 t1].');
    end
end

% ---- cut spikes to the window and recount ----
if win(1) > 0 || win(2) < session.duration_s
    for u = 1:numel(units)
        s = units(u).spikes;
        units(u).spikes = s(s >= win(1) & s < win(2));
        units(u).nSpikes = numel(units(u).spikes);
        units(u).firingRate = units(u).nSpikes / diff(win);
        if units(u).nSpikes > 1
            units(u).pctRefr = 100 * mean(diff(units(u).spikes) < 0.0015);
        else
            units(u).pctRefr = NaN;
        end
    end
end

% ---- filter ----
keep = [units.nSpikes] >= opt.MinSpikes & [units.pctRefr] < opt.MaxPctRefr;
units = units(keep);

session.epoch = epochName;
session.epochWin_s = win;

fprintf('loadUnits: %s | epoch %s (%.1f-%.1f s, %.1f min) | %d of %d units | %d spikes\n', ...
    session.id, epochName, win(1), win(2), diff(win)/60, ...
    numel(units), numel(S.units), sum([units.nSpikes]));

end
