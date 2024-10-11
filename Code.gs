function doPost(e) {
  return handleRequest(e);
}

function doGet(e) {
  if (e.parameter.action === 'getLeaderboard') {
    return getRecruiterLeaderboard();
  }
  else if (e.parameter.action === 'getAnalytics') {
    return getAnalyticsData();
  }
  return handleRequest(e);
}
function getRecruiterLeaderboard() {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
  var data = sheet.getDataRange().getValues();
  var recruiterStats = {};
  
  // Skip the header row
  for (var i = 1; i < data.length; i++) {
    var recruiter = data[i][8]; // Assuming recruiter is in column I (index 8)
    if (recruiter && recruiter !== 'N/A') {
      recruiterStats[recruiter] = (recruiterStats[recruiter] || 0) + 1;
    }
  }
  
  var leaderboard = Object.keys(recruiterStats).map(function(recruiter) {
    return {
      recruiter: recruiter,
      count: recruiterStats[recruiter]
    };
  });
  
  leaderboard.sort(function(a, b) {
    return b.count - a.count;
  });
  
  var output = ContentService.createTextOutput();
  output.setContent(JSON.stringify(leaderboard));
  output.setMimeType(ContentService.MimeType.JSON);
  return output;
}
// Fetch the analytics data from the sheet
function getAnalyticsData() {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
  var data = sheet.getDataRange().getValues();

  var totalRecruits = 0;
  var recruitsThisWeek = 0;
  var recruitsThisDay = 0; // New variable for today's recruits
  var totalAge = 0;
  var recruiterCount = {};
  var collegeCount = {};
  var committeeCount = {};

  var now = new Date();
  var oneWeekAgo = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 7);
  var todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()); // Start of today
  var todayEnd = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1); // End of today

  // Skip the header row
  for (var i = 1; i < data.length; i++) {
    var recruitDate = new Date(data[i][6]); // Assuming timestamp is in column G (index 6)
    totalRecruits++;

    // Calculate recruits within the last week
    if (recruitDate >= oneWeekAgo) {
      recruitsThisWeek++;
    }

    // Calculate recruits for today
    if (recruitDate >= todayStart && recruitDate < todayEnd) {
      recruitsThisDay++; // Increment for recruits today
    }

    // Handle committee distribution
    var committee = data[i][5]; // Assuming committee is in column F (index 5)
    committeeCount[committee] = (committeeCount[committee] || 0) + 1;

    // Handle college distribution
    var college = data[i][4]; // Assuming college is in column E (index 4)
    collegeCount[college] = (collegeCount[college] || 0) + 1;

    // Handle recruiter stats (optional)
    var recruiter = data[i][8]; // Assuming recruiter is in column I (index 8)
    if (recruiter) {
      recruiterCount[recruiter] = (recruiterCount[recruiter] || 0) + 1;
    }
  }

  var analyticsData = {
    totalRecruits: totalRecruits,
    recruitsThisWeek: recruitsThisWeek,
    recruitsThisDay: recruitsThisDay, // Include this day
    committeeDistribution: committeeCount,
    collegeDistribution: collegeCount,
  };

  // Return the analytics data as JSON
  var output = ContentService.createTextOutput();
  output.setContent(JSON.stringify(analyticsData));
  output.setMimeType(ContentService.MimeType.JSON);
  return output;
}

// Existing handleRequest function for processing POST requests
function handleRequest(e) {
  var output = ContentService.createTextOutput();
  var result = {};

  try {
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
    var data;
    
    if (e && e.postData && e.postData.contents) {
      data = JSON.parse(e.postData.contents);
    } else if (e && e.parameter) {
      data = e.parameter;
    } else {
      throw new Error("No data received");
    }

    Logger.log("Parsed data: " + JSON.stringify(data));

    // Verify all required fields are present
    var requiredFields = ['id', 'name', 'email', 'phone', 'college', 'committee', 'timestamp', 'recruiter'];
    for (var field of requiredFields) {
      if (!data.hasOwnProperty(field)) {
        throw new Error("Missing required field: " + field);
      }
    }

    // Check for duplicates
    var values = sheet.getDataRange().getValues();
    var isDuplicate = false;
    
    for (var i = 1; i < values.length; i++) {
      if (values[i][2] === data.email || values[i][3] === data.phone) {
        isDuplicate = true;
        break;
      }
    }

    if (!isDuplicate) {
      sheet.appendRow([
        data.id,
        data.name,
        data.email,
        data.phone,
        data.college,
        data.committee,
        data.timestamp,
        data.profileImagePath || 'N/A',
        data.recruiter
      ]);
      result.status = "success";
      result.message = "Data successfully appended to sheet";
    } else {
      result.status = "error";
      result.message = "Duplicate entry found";
    }

  } catch (error) {
    result.status = "error";
    result.message = "Error: " + error.message;
    Logger.log("Error in handleRequest: " + error.message);
  }

  output.setContent(JSON.stringify(result));
  output.setMimeType(ContentService.MimeType.JSON);
  return output;
}
