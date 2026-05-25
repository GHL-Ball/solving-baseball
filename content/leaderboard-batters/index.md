---
title: "Batters Leaderboard"
---

<link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/jquery.dataTables.min.css">
<style>
.filter-row { display: flex; gap: 2rem; align-items: center; flex-wrap: wrap; margin-bottom: 1rem; }
</style>

<div class="filter-row">
  <div>
    <label for="yearFilter">シーズン：</label>
    <select id="yearFilter">
      <option value="">All</option>
      <option value="2021">2021</option>
      <option value="2022">2022</option>
      <option value="2023">2023</option>
      <option value="2024">2024</option>
      <option value="2025">2025</option>
    </select>
  </div>
  <div>
    <label for="minPitches">最小Pitches数：<span id="minPitchesVal">500</span></label><br>
    <input type="range" id="minPitches" min="1" max="3000" value="500" step="50" style="width:200px;">
  </div>
</div>

<table id="batterTable" class="display" style="width:100%">
  <thead>
    <tr>
      <th>Name</th>
      <th>Year</th>
      <th>Pitches</th>
      <th>Opponent Stuff RV/70</th>
      <th>Opponent Pitch RV/150</th>
      <th>wOBA</th>
    </tr>
  </thead>
</table>

<script src="https://code.jquery.com/jquery-3.7.0.min.js"></script>
<script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/PapaParse/5.4.1/papaparse.min.js"></script>
<script>
var playersMap = {};
var batterData = [];
var loadedCount = 0;
var dtBatter = null;

function tryRender() {
  if (loadedCount < 2) return;

  batterData.forEach(function(r) {
    r.name = playersMap[String(r.batter_id)] || String(r.batter_id);
  });

  dtBatter = $("#batterTable").DataTable({
    data: batterData.filter(r => r.pitches >= 500),
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

  $("#yearFilter").on("change", function() { applyFilter(); });
  $("#minPitches").on("input", function() {
    $("#minPitchesVal").text($(this).val());
    applyFilter();
  });
}

function applyFilter() {
  var yr   = $("#yearFilter").val();
  var minN = parseInt($("#minPitches").val());
  $.fn.dataTable.ext.search = [];
  $.fn.dataTable.ext.search.push(function(settings, data, dataIndex, rowData) {
    if (yr && String(rowData.year) !== yr) return false;
    if (rowData.pitches < minN) return false;
    return true;
  });
  dtBatter.draw();
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
    batterData = results.data.filter(r => r.batter_id);
    loadedCount++; tryRender();
  }
});
</script>