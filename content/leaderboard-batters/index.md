---
title: "Batters Leaderboard"
---

<link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/jquery.dataTables.min.css">
<style>
.tab-buttons { display: flex; gap: 0.5rem; margin-bottom: 1.5rem; flex-wrap: wrap; }
.tab-btn {
  padding: 6px 18px; cursor: pointer; border: 1px solid #888;
  border-radius: 4px; background: transparent; color: inherit; font-size: 0.95rem;
}
.tab-btn.active { background: #555; color: #fff; border-color: #555; }
.tab-content { display: none; }
.tab-content.active { display: block; }
.filter-row { display: flex; gap: 2rem; align-items: center; flex-wrap: wrap; margin-bottom: 1rem; }
.dataTables_wrapper { overflow-x: auto; }
.col-btn {
  padding: 4px 12px; cursor: pointer; border: 1px solid #888;
  border-radius: 4px; background: transparent; color: inherit; font-size: 0.85rem;
}
.col-btn.active { background: #555; color: #fff; border-color: #555; }
.slider-group { display: flex; align-items: center; gap: 0.5rem; }
</style>

<div class="tab-buttons">
  <button class="tab-btn active" onclick="switchTab('opponent', event)">Opponent Pitch Model</button>
  <button class="tab-btn" onclick="switchTab('xwoba', event)">xwOBA</button>
</div>

<div id="tab-opponent" class="tab-content active">
  <div class="filter-row">
    <div>
      <label for="oppYearFilter">シーズン：</label>
      <select id="oppYearFilter">
        <option value="">All</option>
        <option value="2021">2021</option>
        <option value="2022">2022</option>
        <option value="2023">2023</option>
        <option value="2024">2024</option>
        <option value="2025">2025</option>
      </select>
    </div>
    <div>
      <label>最小Pitches数：</label>
      <div class="slider-group">
        <input type="range" id="oppMinPitches" min="1" max="3000" value="500" step="1" style="width:150px;">
        <input type="number" id="oppMinPitchesNum" min="1" max="3000" value="500" style="width:70px;">
      </div>
    </div>
  </div>
  <table id="batterTable" class="display" style="width:100%">
    <thead>
      <tr>
        <th>Name</th><th>Year</th><th>Pitches</th>
        <th>Opponent Stuff RV/70</th><th>Opponent Pitch RV/150</th><th>wOBA</th>
      </tr>
    </thead>
  </table>
</div>

<div id="tab-xwoba" class="tab-content">
  <div class="filter-row">
    <div>
      <label for="xwobaYearFilter">シーズン：</label>
      <select id="xwobaYearFilter">
        <option value="">All</option>
        <option value="2021">2021</option>
        <option value="2022">2022</option>
        <option value="2023">2023</option>
        <option value="2024">2024</option>
        <option value="2025">2025</option>
      </select>
    </div>
    <div>
      <label>最小PA数：</label>
      <div class="slider-group">
        <input type="range" id="xwobaMinPA" min="1" max="700" value="300" step="1" style="width:150px;">
        <input type="number" id="xwobaMinPANum" min="1" max="700" value="300" style="width:70px;">
      </div>
    </div>
    <div>
      <span>表示列：</span>
      <button class="col-btn active" onclick="setColGroup('woba', event)">wOBA系</button>
      <button class="col-btn" onclick="setColGroup('wobacon', event)">wOBAcon系</button>
      <button class="col-btn" onclick="setColGroup('both', event)">両方</button>
    </div>
  </div>
  <table id="xwobaBatTable" class="display" style="width:100%">
    <thead>
      <tr>
        <th>Name</th><th>Year</th><th>PA</th>
        <th>wOBA</th>
        <th>xwOBA (ev+la)</th>
        <th>xwOBA (ev+la+sa)</th>
        <th>wOBA-xwOBA (2p)</th>
        <th>wOBA-xwOBA (3p)</th>
        <th>xwOBA (3p-2p)</th>
        <th>wOBAcon</th>
        <th>xwOBAcon (ev+la)</th>
        <th>xwOBAcon (ev+la+sa)</th>
        <th>wOBAcon-xwOBAcon (2p)</th>
        <th>wOBAcon-xwOBAcon (3p)</th>
        <th>xwOBAcon (3p-2p)</th>
      </tr>
    </thead>
  </table>
</div>

<script src="https://code.jquery.com/jquery-3.7.0.min.js"></script>
<script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/PapaParse/5.4.1/papaparse.min.js"></script>
<script>
var playersMap = {};
var oppData = [];
var xwobaBatData = [];
var loadedCount = 0;
var dtBatter = null;
var dtXwobaBat = null;

var filters = {
  opp:   { year: "", minN: 500 },
  xwoba: { year: "", minN: 300 }
};

var colGroups = {
  woba:    [3,4,5,6,7,8],
  wobacon: [9,10,11,12,13,14],
  both:    [3,4,5,6,7,8,9,10,11,12,13,14]
};

$.fn.dataTable.ext.search.push(function(settings, data, dataIndex, rowData) {
  var id = settings.nTable.id;
  if (id === "batterTable") {
    if (filters.opp.year && String(rowData.year) !== filters.opp.year) return false;
    if ((rowData.pitches || 0) < filters.opp.minN) return false;
  }
  if (id === "xwobaBatTable") {
    if (filters.xwoba.year && String(rowData.year) !== filters.xwoba.year) return false;
    if ((rowData.pa || 0) < filters.xwoba.minN) return false;
  }
  return true;
});

function syncSliderNum(sliderId, numId, filterKey, field) {
  $("#" + sliderId).on("input", function() {
    var v = parseInt($(this).val());
    $("#" + numId).val(v);
    filters[filterKey][field] = v;
    if (filterKey === "opp" && dtBatter) dtBatter.draw();
    if (filterKey === "xwoba" && dtXwobaBat) dtXwobaBat.draw();
  });
  $("#" + numId).on("input", function() {
    var v = parseInt($(this).val()) || 0;
    $("#" + sliderId).val(v);
    filters[filterKey][field] = v;
    if (filterKey === "opp" && dtBatter) dtBatter.draw();
    if (filterKey === "xwoba" && dtXwobaBat) dtXwobaBat.draw();
  });
}

function tryRender() {
  if (loadedCount < 3) return;

  [oppData, xwobaBatData].forEach(function(arr) {
    arr.forEach(function(r) {
      r.name = playersMap[String(r.batter_id)] || String(r.batter_id);
    });
  });

  dtBatter = $("#batterTable").DataTable({
    data: oppData,
    columns: [
      { data: "name" },
      { data: "year" },
      { data: "pitches" },
      { data: "stuff_rv_70",  render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "pitch_rv_150", render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "woba_fg",      render: d => d != null ? (+d).toFixed(3) : "-" }
    ],
    order: [[3, "desc"]],
    pageLength: 25
  });

  dtXwobaBat = $("#xwobaBatTable").DataTable({
    data: xwobaBatData,
    columns: [
      { data: "name" },
      { data: "year" },
      { data: "pa" },
      { data: "woba",                          render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "xwoba_ev_la",                   render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "xwoba_ev_la_sa",                render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "woba_minus_xwoba_2p",           render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "woba_minus_xwoba_3p",           render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "xwoba_3p_minus_xwoba_2p",       render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "wobacon",                       render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "xwobacon_ev_la",                render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "xwobacon_ev_la_sa",             render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "wobacon_minus_xwobacon_2p",     render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "wobacon_minus_xwobacon_3p",     render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "xwobacon_3p_minus_xwobacon_2p", render: d => d != null ? (+d).toFixed(3) : "-" }
    ],
    order: [[3, "desc"]],
    pageLength: 25,
    columnDefs: [{ targets: [9,10,11,12,13,14], visible: false }]
  });

  $("#oppYearFilter").on("change", function() {
    filters.opp.year = $(this).val();
    dtBatter.draw();
  });
  $("#xwobaYearFilter").on("change", function() {
    filters.xwoba.year = $(this).val();
    dtXwobaBat.draw();
  });

  syncSliderNum("oppMinPitches", "oppMinPitchesNum", "opp",   "minN");
  syncSliderNum("xwobaMinPA",    "xwobaMinPANum",    "xwoba", "minN");

  dtBatter.draw();
  dtXwobaBat.draw();
}

function setColGroup(group, e) {
  document.querySelectorAll(".col-btn").forEach(el => el.classList.remove("active"));
  e.target.classList.add("active");
  var allCols = [3,4,5,6,7,8,9,10,11,12,13,14];
  colGroups[group].forEach(i => dtXwobaBat.column(i).visible(true));
  allCols.filter(i => !colGroups[group].includes(i)).forEach(i => dtXwobaBat.column(i).visible(false));
}

function switchTab(name, e) {
  document.querySelectorAll(".tab-content").forEach(el => el.classList.remove("active"));
  document.querySelectorAll(".tab-btn").forEach(el => el.classList.remove("active"));
  document.getElementById("tab-" + name).classList.add("active");
  e.target.classList.add("active");
  if (name === "opponent" && dtBatter) dtBatter.columns.adjust().draw();
  if (name === "xwoba" && dtXwobaBat) dtXwobaBat.columns.adjust().draw();
}

Papa.parse("/solving-baseball/data/players.csv", {
  download: true, header: true,
  complete: function(results) {
    results.data.forEach(r => { if (r.MLBAMID) playersMap[String(r.MLBAMID)] = r.Name; });
    loadedCount++; tryRender();
  }
});
Papa.parse("/solving-baseball/data/leaderboards/opponent_pitch_model_gbdt_2021_2025.csv", {
  download: true, header: true, dynamicTyping: true,
  complete: function(results) {
    oppData = results.data.filter(r => r.batter_id);
    loadedCount++; tryRender();
  }
});
Papa.parse("/solving-baseball/data/leaderboards/xwoba_bat_2021_2025.csv", {
  download: true, header: true, dynamicTyping: true,
  complete: function(results) {
    xwobaBatData = results.data.filter(r => r.batter_id);
    loadedCount++; tryRender();
  }
});
</script>