function [psth, t_ms, raster] = plotEvokedSpikes(units, events, unitIdx, varargin)
% plotEvokedSpikes   Raster + PSTH for one unit, aligned to stimulus onset.
%
% PURPOSE
% -------
% The quickest way to see whether a unit is real and responsive: align its spikes to every
% stimulus onset and look. 
%
% INPUTS
% ------
% REQUIRES THE TASK EPOCH. The `spontaneous` epoch is the screen-off block: it contains no
% stimuli, so there is nothing to align to and this function will tell you so.
%
%   units      struct array from loadUnits — load with 'Epoch', 'task' (or 'all')
%   events     event struct from loadUnits
%   unitIdx    index into `units`, NOT the cluster id. Convert with find([units.id] == n).
%
%   Name/value:
%     'AlignCode'  event code to align on (default 11 = stimulus on)
%     'Window'     [pre post] in ms around the event (default [-200 500])
%     'BinMs'      PSTH bin width in ms (default 10)
%     'Plot'       true (default). false returns the numbers without drawing.
%
% OUTPUTS
% -------
%   psth     firing rate in spikes/s, one value per bin
%   t_ms     bin centres, ms relative to the alignment event
%   raster   {nEvents x 1} cell, spike times in ms relative to each event
%
% EXAMPLES
% --------
%   [units, session, events] = loadUnits('Epoch', 'task');
%   plotEvokedSpikes(units, events, 1);
%
%   % find the most active units first
%   [~, ord] = sort([units.firingRate], 'descend');
%   plotEvokedSpikes(units, events, ord(1));
%
% See also: loadUnits

p = inputParser;
p.addParameter('AlignCode', 11, @isnumeric);
p.addParameter('Window', [-200 500], @(x) isnumeric(x) && numel(x) == 2);
p.addParameter('BinMs', 10, @isnumeric);
p.addParameter('Plot', true, @islogical);
p.parse(varargin{:});
opt = p.Results;

if unitIdx < 1 || unitIdx > numel(units)
    error('plotEvokedSpikes:badIdx', 'unitIdx must be between 1 and %d.', numel(units));
end

alignT = events.times_s(events.codes == opt.AlignCode);
if isempty(alignT)
    error('plotEvokedSpikes:noEvents', 'No events with code %d.', opt.AlignCode);
end

spk = units(unitIdx).spikes;

% Alignment events must lie inside the loaded epoch. Take the epoch span from ALL units,
% not from this one -- a unit that happens to be silent early or late would otherwise
% shrink the window and silently discard valid events.
hasSpk = ~cellfun(@isempty, {units.spikes});
if ~any(hasSpk)
    error('plotEvokedSpikes:noSpikes', 'No unit has any spikes. Check how `units` was loaded.');
end
lo = min(arrayfun(@(u) u.spikes(1),   units(hasSpk)));
hi = max(arrayfun(@(u) u.spikes(end), units(hasSpk)));

if ~any(alignT >= lo & alignT <= hi)
    error('plotEvokedSpikes:eventsOutsideEpoch', ...
        ['No code-%d events fall inside the loaded data.\n' ...
         '  loaded spikes span : %.1f - %.1f s\n' ...
         '  code-%d events span: %.1f - %.1f s\n\n' ...
         'If you loaded the ''spontaneous'' epoch this is expected, not a bug: it is the ' ...
         '30-minute screen-off block and contains no stimuli by design, so there is ' ...
         'nothing to align to. Reload with loadUnits(''Epoch'', ''task'').'], ...
        opt.AlignCode, lo, hi, opt.AlignCode, min(alignT), max(alignT));
end

alignT = alignT(alignT + opt.Window(1)/1000 >= lo & alignT + opt.Window(2)/1000 <= hi);
nEv = numel(alignT);

edges = opt.Window(1) : opt.BinMs : opt.Window(2);
t_ms  = edges(1:end-1) + opt.BinMs/2;
counts = zeros(1, numel(t_ms));
raster = cell(nEv, 1);

for e = 1:nEv
    rel = (spk - alignT(e)) * 1000;                        % ms relative to the event
    rel = rel(rel >= opt.Window(1) & rel < opt.Window(2));
    raster{e} = rel;
    counts = counts + histcounts(rel, edges);
end

psth = counts / max(nEv, 1) / (opt.BinMs / 1000);          % spikes/s

if ~opt.Plot, return; end

nPts = sum(cellfun(@numel, raster));
if nEv == 0 || nPts == 0
    warning('plotEvokedSpikes:nothingToDraw', ...
        ['Nothing to plot for unit index %d (id %d): %d events, %d spikes in window.\n' ...
         'Check that unitIdx is an INDEX into `units`, not a cluster id — ' ...
         'use find([units.id] == <id>) to convert.'], ...
        unitIdx, units(unitIdx).id, nEv, nPts);
    return
end

figure('Color', 'w', 'Name', sprintf('unit %d', units(unitIdx).id));

% ---- raster ----
% Drawn as ONE line object with NaN separators. One plot call per event creates hundreds of
% graphics objects, which is slow enough on some setups (remote desktops, software OpenGL)
% that the figure can come up blank or appear to hang.
x = []; y = [];
for e = 1:nEv
    if isempty(raster{e}), continue; end
    x = [x; raster{e}(:); NaN];                                  %#ok<AGROW>
    y = [y; e * ones(numel(raster{e}), 1); NaN];                 %#ok<AGROW>
end

subplot(3, 1, [1 2]); hold on
plot(x, y, '.', 'MarkerSize', 3, 'Color', [0 0 0]);
plot([0 0], [0 nEv+1], 'r-', 'LineWidth', 1);
xlim(opt.Window); ylim([0 nEv+1]);
ylabel('event #'); set(gca, 'TickDir', 'out'); box off
title(sprintf('unit %d  |  ch %d, depth %.0f um  |  %d spikes, %.1f Hz, %.2f%% refr  |  %d events', ...
    units(unitIdx).id, units(unitIdx).channel, units(unitIdx).depth_um, ...
    units(unitIdx).nSpikes, units(unitIdx).firingRate, units(unitIdx).pctRefr, nEv), ...
    'FontWeight', 'normal');

% ---- PSTH ----
subplot(3, 1, 3); hold on
bar(t_ms, psth, 1, 'FaceColor', [0.35 0.5 0.7], 'EdgeColor', 'none');
yl = ylim; plot([0 0], [0 max(yl(2), eps)], 'r-', 'LineWidth', 1);
xlim(opt.Window);
xlabel(sprintf('time from event code %d (ms)', opt.AlignCode));
ylabel('spikes/s'); set(gca, 'TickDir', 'out'); box off

drawnow

end
