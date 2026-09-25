function [units, session, events] = loadUnits(varargin)
% loadUnits   Load the Katniss MT units, optionally restricted to an epoch or filtered.
%
% PURPOSE
% -------
% One call to get spike times and unit metadata.
%
% WHICH SET YOU GET
% -----------------
% The file holds 301 units: the clusters a manual waveform screen accepted, all inside the
% cortical bounds. That is the BASE set, and it is the same unit definition used everywhere
% else in this dataset. One flag refines it:
%
%   units.passQC   176 units. Refractory violations under 2%, more than 1000 spikes, not a
%                  sorting duplicate. THE WELL-ISOLATED ONES -- start here.
%                  session.qcCriteria spells it out.
%
% 'OnlyQC', true applies it for you:
%
%   units = loadUnits('OnlyQC', true);                     % 176 units
%   units = loadUnits('OnlyQC', true, 'Epoch', 'task');    % the SAME 176, task spikes only
%
% ⭐ passQC IS THE SAME IN EVERY EPOCH, on purpose. It is computed once over the whole
% recording and never recomputed here. Isolation is a property of the unit, not of the window
% you analyse -- the 100-minute estimate uses every spike and is the best one available, and a
% set that changed with the epoch could not be compared across epochs. If you need enough
% spikes IN a window to compute something, that is a power question: filter on 'MinSpikes'
% after choosing the epoch.
%
% NOTHING HAS EVER MERGED OR SPLIT A CLUSTER. The boundaries are Kilosort 4's. Expect
% near-zero-lag cross-correlogram peaks from oversplit clusters -- see the README.
%
% MORE THAN ONE SESSION
% ---------------------
% Every session in data/ is a file named katniss_<YYMMDD>_units.mat, and they all have the
% same fields. With one file present it loads with no arguments; with several, name the one
% you want and the error message lists what is there:
%
%   units = loadUnits('Session', '251121');
%
% INPUTS (all optional, name/value)
% ---------------------------------
%   'Session'     'YYMMDD' of the session to load. Only needed when data/ holds more than one.
%   'File'        explicit path to a .mat; overrides 'Session'
%   'OnlyQC'      logical, default false. Keep only units passing session.qcCriteria.
%   'Epoch'       'all' (default) | 'restPre' | 'task' | 'restPost' | [t0 t1] in seconds
%                    restPre  = rest before the first task event, SCREEN ON
%                    task     = first to last task event
%                    restPost = rest after the last task event, SCREEN OFF
%                               ('spontaneous' is an accepted alias)
%                    ⚠️ restPre and restPost are not the same condition -- screen on vs off.
%                    Do not pool them. Some sessions have almost none of one or the other;
%                    an empty window raises an error rather than returning nothing.
%                    Spike times are cut to the window. They keep ABSOLUTE times, so they
%                    still line up with events.times_s.
%   'MinSpikes'   keep units with at least this many spikes IN THE EPOCH (default 0)
%   'MaxPctRefr'  keep units whose refractory violation rate is below this (default Inf,
%                    i.e. no filtering -- units with too few spikes to have a rate are
%                    kept when this is Inf and dropped when you set a real threshold)
%
% OUTPUTS
% -------
%   units     1 x nUnits struct array — see README for every field
%   session   recording metadata: epochs, laminar, qcCriteria, curation
%   events    behavioural event times and codes, on the same clock as the spikes
%
% EXAMPLES
% --------
%   units = loadUnits('OnlyQC', true, 'Epoch', 'task');     % the connectivity-ready set
%   units = loadUnits;                                      % all 301, unfiltered
%   [units, session, events] = loadUnits('Epoch', 'spontaneous');
%
% See also: plotEvokedSpikes

p = inputParser;
p.addParameter('Session', '', @(x) ischar(x) || isstring(x) || isnumeric(x));
p.addParameter('File', '', @(x) ischar(x) || isstring(x));
p.addParameter('OnlyQC', false, @(x) islogical(x) || isnumeric(x));
p.addParameter('Epoch', 'all');
p.addParameter('MinSpikes', 0, @isnumeric);
p.addParameter('MaxPctRefr', Inf, @isnumeric);
p.parse(varargin{:});
opt = p.Results;

dataDir = fullfile(fileparts(mfilename('fullpath')), 'data');
f = localResolveFile(dataDir, opt.File, opt.Session);

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
    % 'spontaneous' is the old name for the screen-off block after the task. Kept as an
    % alias so code written against the first release still runs.
    epochName = lower(char(opt.Epoch));
    switch epochName
        case 'all',                        win = [0, session.duration_s];
        case 'restpre',                    win = session.epochs.restPre;  epochName = 'restPre';
        case 'task',                       win = session.epochs.task;
        case {'restpost', 'spontaneous'},  win = session.epochs.restPost; epochName = 'restPost';
        otherwise
            error('loadUnits:badEpoch', ...
                ['Epoch must be ''all'', ''restPre'', ''task'', ''restPost'' ' ...
                 '(alias ''spontaneous''), or [t0 t1].']);
    end
    if diff(win) <= 0
        error('loadUnits:emptyEpoch', ...
            'Epoch ''%s'' is empty on session %s (window [%.1f %.1f] s).', ...
            epochName, session.id, win(1), win(2));
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

    % passQC is deliberately NOT recomputed here. It describes the unit's isolation over the
    % whole recording, which is the best estimate available and is the same in every epoch --
    % so the unit set stays identical across epochs and remains comparable between them. A
    % window-specific recomputation would only add noise and silently change the set.
    % pctRefr and nSpikes above ARE per-epoch, because they describe the spikes you now hold.
end

% ---- filter ----
% A unit with fewer than two spikes has no refractory rate at all. Comparing NaN < Inf is
% false, so a naive test would drop such units even under the default no-op threshold.
keep = [units.nSpikes] >= opt.MinSpikes;
if isfinite(opt.MaxPctRefr)
    keep = keep & [units.pctRefr] < opt.MaxPctRefr;
end
if opt.OnlyQC
    if ~isfield(units, 'passQC')
        error('loadUnits:noPassQC', ...
            'This file has no passQC field -- it predates the flag. Re-export it.');
    end
    keep = keep & logical([units.passQC]);
end
units = units(keep);

session.epoch = epochName;
session.epochWin_s = win;

[~, base, ext] = fileparts(f);
fprintf('loadUnits: %s | %s | epoch %s (%.1f-%.1f s, %.1f min) | %d of %d units%s | %d spikes\n', ...
    session.id, [base ext], epochName, win(1), win(2), diff(win)/60, ...
    numel(units), numel(S.units), repmat(' [passQC]', 1, opt.OnlyQC), sum([units.nSpikes]));

end

% =========================================================================================
function f = localResolveFile(dataDir, fileOpt, sessionOpt)
% Find the session file. One session in data/ loads with no arguments; several require
% 'Session' rather than silently picking one.
f = char(fileOpt);
if ~isempty(f)
    if ~isfile(f), error('loadUnits:noFile', 'File not found: %s', f); end
    return
end

d = dir(fullfile(dataDir, 'katniss_*_units.mat'));
names = {d.name};
dates = regexp(names, '(\d{6})', 'match', 'once');

if ~isempty(sessionOpt)
    want = char(string(sessionOpt));
    tok = regexp(want, '(\d{6})', 'match', 'once');
    if isempty(tok)
        error('loadUnits:badSession', ...
            'Session must contain a YYMMDD date, e.g. ''251121'' (got ''%s'').', want);
    end
    k = find(strcmp(dates, tok), 1);
    if isempty(k)
        error('loadUnits:noSession', '\nSession %s is not in %s\n\nAvailable: %s\n', ...
            tok, dataDir, localList(dates));
    end
    f = fullfile(dataDir, names{k});
    return
end

switch numel(names)
    case 0
        error('loadUnits:noFile', ['\nNo session files found in:\n  %s\n\n' ...
            'The data is not stored in this repository. Download the katniss_*_units.mat\n' ...
            'file(s) using the link in the "Getting the data" section of the README and\n' ...
            'put them in that folder. Or pass a path directly:\n\n' ...
            '    loadUnits(''File'', ''C:\\path\\to\\units.mat'')\n'], dataDir);
    case 1
        f = fullfile(dataDir, names{1});
    otherwise
        error('loadUnits:ambiguousSession', ['\n%d sessions are available: %s\n\n' ...
            'Say which one:\n\n    loadUnits(''Session'', ''%s'')\n'], ...
            numel(names), localList(dates), dates{1});
end
end

function s = localList(dates)
s = strjoin(dates, ', ');
if isempty(s), s = '(none)'; end
end
