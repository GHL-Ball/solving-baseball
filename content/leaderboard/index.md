---
title: "Pitchers Leaderboard"
---

<link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/jquery.dataTables.min.css">

<div style="margin-bottom: 1rem; display: flex; gap: 2rem; align-items: center; flex-wrap: wrap;">
  <div>
    <label for="yearFilter">シーズン：</label>
    <select id="yearFilter">
      <option value="">All</option>
      <option value="2023">2023</option>
      <option value="2024">2024</option>
      <option value="2025">2025</option>
    </select>
  </div>
  <div>
    <label for="minPitches">最小投球数：<span id="minPitchesVal">100</span></label><br>
    <input type="range" id="minPitches" min="1" max="500" value="100" step="1" style="width:200px;">
  </div>
</div>

<table id="disruptionTable" class="display" style="width:100%">
  <thead>
    <tr>
      <th>Name</th>
      <th>Year</th>
      <th>Swings</th>
      <th>Disruption</th>
      <th>Adjusted Disruption</th>
      <th>Bias</th>
    </tr>
  </thead>
</table>

<script src="https://code.jquery.com/jquery-3.7.0.min.js"></script>
<script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/PapaParse/5.4.1/papaparse.min.js"></script>
<script>
var allData = [];
var playersMap = {};
var dataLoaded = 0;

function tryRender() {
  if (dataLoaded < 2) return;

  // 名前を結合、なければMLBAMIDをそのまま表示
  allData.forEach(function(r) {
    r.name = playersMap[String(r.pitcher_id)] || String(r.pitcher_id);
  });

  var table = $("#disruptionTable").DataTable({
    data: allData.filter(r => r.n_pitches >= 100),
    columns: [
      { data: "name" },
      { data: "year" },
      { data: "n_pitches" },
      { data: "disruption_1", render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "disruption_2", render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "bias_1",       render: d => d != null ? (+d).toFixed(3) : "-" }
    ],
    order: [[3, "desc"]],
    pageLength: 25
  });

  // シーズンフィルター
  $("#yearFilter").on("change", function() {
    applyFilters(table);
  });

  // 最小投球数スライダー
  $("#minPitches").on("input", function() {
    $("#minPitchesVal").text($(this).val());
    applyFilters(table);
  });
}

function applyFilters(table) {
  var yr = $("#yearFilter").val();
  var minN = parseInt($("#minPitches").val());

  // カスタムフィルター
  $.fn.dataTable.ext.search = [];
  $.fn.dataTable.ext.search.push(function(settings, data, dataIndex, rowData) {
    if (yr && String(rowData.year) !== yr) return false;
    if (rowData.n_pitches < minN) return false;
    return true;
  });
  table.draw();
}

// players.csv読み込み
Papa.parse("/solving-baseball/data/players.csv", {
  download: true,
  header: true,
  complete: function(results) {
    results.data.forEach(function(r) {
      if (r.MLBAMID) playersMap[String(r.MLBAMID)] = r.Name;
    });
    dataLoaded++;
    tryRender();
  }
});

// disruption CSV読み込み
Papa.parse("/solving-baseball/data/leaderboards/disruption_2023_2025.csv", {
  download: true,
  header: true,
  dynamicTyping: true,
  complete: function(results) {
    allData = results.data.filter(r => r.pitcher_id);
    dataLoaded++;
    tryRender();
  }
});
</script>