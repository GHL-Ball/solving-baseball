---
title: "Pitchers Leaderboard"
---

<link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/jquery.dataTables.min.css">
<style>
.tab-buttons { display: flex; gap: 0.5rem; margin-bottom: 1.5rem; }
.tab-btn {
  padding: 6px 18px; cursor: pointer; border: 1px solid #888;
  border-radius: 4px; background: transparent; color: inherit; font-size: 0.95rem;
}
.tab-btn.active { background: #555; color: #fff; border-color: #555; }
.tab-content { display: none; }
.tab-content.active { display: block; }
.filter-row { display: flex; gap: 2rem; align-items: center; flex-wrap: wrap; margin-bottom: 1rem; }
.dataTables_wrapper { overflow-x: auto; }
</style>

<div class="tab-buttons">
  <button class="tab-btn active" onclick="switchTab('disruption')">Disruption</button>
  <button class="tab-btn" onclick="switchTab('pitchmodel')">Pitch Model</button>
</div>

<!-- Disruption タブ -->
<div id="tab-disruption" class="tab-content active">
  <div class="filter-row">
    <div>
      <label for="yearFilter1">シーズン：</label>
      <select id="yearFilter1">
        <option value="">All</option>
        <option value="2023">2023</option>
        <option value="2024">2024</option>
        <option value="2025">2025</option>
      </select>
    </div>
    <div>
      <label for="minSwings">最小Swings数：<span id="minSwingsVal">100</span></label><br>
      <input type="range" id="minSwings" min="1" max="500" value="100" step="1" style="width:200px;">
    </div>
  </div>
  <table id="disruptionTable" class="display" style="width:100%">
    <thead>
      <tr>
        <th>Name</th><th>Year</th><th>Swings</th>
        <th>Disruption</th><th>Adjusted Disruption</th><th>Bias</th>
      </tr>
    </thead>
  </table>
</div>

<!-- Pitch Model タブ -->
<div id="tab-pitchmodel" class="tab-content">
  <div class="filter-row">
   <div>
     <label for="yearFilter2">シーズン：</label>
     <select id="yearFilter2">
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
  <table id="pitchmodelTable" class="display" style="width:100%">
    <thead>
      <tr>
        <th>Name</th><th>Year</th><th>Pitches</th>
        <th>Stuff RV/70</th><th>Pitch RV/150</th>
      </tr>
    </thead>
  </table>
</div>

<script src="https://code.jquery.com/jquery-3.7.0.min.js"></script>
<script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/PapaParse/5.4.1/papaparse.min.js"></script>
<script>
var playersMap = {};
var disruptionData = [];
var pitchmodelData = [];
var loadedCount = 0;
var dtDisruption = null;
var dtPitchmodel = null;

function tryRender() {
  if (loadedCount < 3) return;

  // 名前マッピング
  [disruptionData, pitchmodelData].forEach(function(arr) {
    arr.forEach(function(r) {
      var id = String(r.pitcher_id);
      r.name = playersMap[id] || id;
    });
  });

  // Disruption テーブル
  dtDisruption = $("#disruptionTable").DataTable({
    data: disruptionData.filter(r => r.n_pitches >= 100),
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

  // Pitch Model テーブル
  dtPitchmodel = $("#pitchmodelTable").DataTable({
    data: pitchmodelData.filter(r => r.pitches >= 500),
    columns: [
      { data: "name" },
      { data: "year" },
      { data: "pitches" },
      { data: "stuff_rv_70",  render: d => d != null ? (+d).toFixed(3) : "-" },
      { data: "pitch_rv_150", render: d => d != null ? (+d).toFixed(3) : "-" }
    ],
    order: [[3, "desc"]],
    pageLength: 25
  });

  // Disruptionフィルター
  $("#yearFilter1").on("change", function() { applyDisruptionFilter(); });
  $("#minSwings").on("input", function() {
    $("#minSwingsVal").text($(this).val());
    applyDisruptionFilter();
  });

  // Pitch Modelフィルター
  $("#yearFilter2").on("change", function() { applyPitchmodelFilter(); });
  $("#minPitches").on("input", function() {
    $("#minPitchesVal").text($(this).val());
    applyPitchmodelFilter();
  });
}

function applyDisruptionFilter() {
  var yr   = $("#yearFilter1").val();
  var minN = parseInt($("#minSwings").val());
  $.fn.dataTable.ext.search = [];
  $.fn.dataTable.ext.search.push(function(settings, data, dataIndex, rowData) {
    if (settings.nTable.id !== "disruptionTable") return true;
    if (yr && String(rowData.year) !== yr) return false;
    if (rowData.n_pitches < minN) return false;
    return true;
  });
  dtDisruption.draw();
}

function applyPitchmodelFilter() {
  var yr   = $("#yearFilter2").val();
  var minN = parseInt($("#minPitches").val());
  $.fn.dataTable.ext.search = [];
  $.fn.dataTable.ext.search.push(function(settings, data, dataIndex, rowData) {
    if (settings.nTable.id !== "pitchmodelTable") return true;
    if (yr && String(rowData.year) !== yr) return false;
    if (rowData.pitches < minN) return false;
    return true;
  });
  dtPitchmodel.draw();
}

function switchTab(name) {
  document.querySelectorAll(".tab-content").forEach(el => el.classList.remove("active"));
  document.querySelectorAll(".tab-btn").forEach(el => el.classList.remove("active"));
  document.getElementById("tab-" + name).classList.add("active");
  event.target.classList.add("active");
  // タブ切り替え時にDataTablesのカラム幅を再計算
  if (name === "disruption" && dtDisruption) dtDisruption.columns.adjust().draw();
  if (name === "pitchmodel" && dtPitchmodel) dtPitchmodel.columns.adjust().draw();
}

// players.csv
Papa.parse("/solving-baseball/data/players.csv", {
  download: true, header: true,
  complete: function(results) {
    results.data.forEach(r => { if (r.MLBAMID) playersMap[String(r.MLBAMID)] = r.Name; });
    loadedCount++; tryRender();
  }
});

// disruption CSV
Papa.parse("/solving-baseball/data/leaderboards/disruption_2023_2025.csv", {
  download: true, header: true, dynamicTyping: true,
  complete: function(results) {
    disruptionData = results.data.filter(r => r.pitcher_id);
    loadedCount++; tryRender();
  }
});

// pitch model CSV
Papa.parse("/solving-baseball/data/leaderboards/pitch_model_gbdt_2021_2025.csv", {
  download: true, header: true, dynamicTyping: true,
  complete: function(results) {
    pitchmodelData = results.data.filter(r => r.pitcher_id);
    loadedCount++; tryRender();
  }
});
</script>