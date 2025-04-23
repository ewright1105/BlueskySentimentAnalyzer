export const formatTimestamp = (unixTimestampMs) => {
  if (typeof unixTimestampMs !== 'number' || isNaN(unixTimestampMs) || unixTimestampMs === null) {
      return "N/A";
  }
  try {
    // Use a consistent, unambiguous format if possible, or locale default
    return new Date(unixTimestampMs).toLocaleString(undefined, {
        year: 'numeric', month: 'short', day: 'numeric',
        hour: '2-digit', minute: '2-digit'
    });
  } catch (e) {
    console.error("Error formatting timestamp:", unixTimestampMs, e);
    return "Invalid Date";
  }
};

export const formatXAxis = (unixTimestampMs) => {
   if (typeof unixTimestampMs !== 'number' || isNaN(unixTimestampMs) || unixTimestampMs === null) {
       return "";
   }
   try {
     // Consider adding date if data spans multiple days
     return new Date(unixTimestampMs).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
   } catch(e) {
     console.error("Error formatting X-axis timestamp:", unixTimestampMs, e);
     return "";
   }
};

export const parseApiTimestampToMillis = (apiTimestamp) => {
    if (apiTimestamp === null || apiTimestamp === undefined) {
        return null;
    }

    // If it's already a number, assume it might be seconds or milliseconds
    if (typeof apiTimestamp === 'number') {
        // Simple heuristic: if timestamp is less than ~ Sep 2001, assume seconds
        // If greater, assume milliseconds. Adjust threshold if needed.
        if (apiTimestamp < 1000000000000) { // Less than 13 digits, likely seconds
             return apiTimestamp * 1000;
        } else { // Likely milliseconds
             return apiTimestamp;
        }
    }

    if (typeof apiTimestamp === 'string') {
        // Try parsing common formats (ISO 8601, etc.)
        const parsedDate = new Date(apiTimestamp);
        if (!isNaN(parsedDate.getTime())) {
            return parsedDate.getTime();
        }
        // Add more specific parsing if needed for other formats
    }
    console.warn("Could not parse timestamp:", apiTimestamp, typeof apiTimestamp);
    return null; // Return null if parsing fails
};


export const formatDuration = (topic) => {
      if (!topic || !topic.intervalLength || !topic.numberOfIntervals || !topic.intervalUnit) {
          return "Duration info incomplete";
      }
      const intervalText = topic.numberOfIntervals === 1 ? 'interval' : 'intervals';
      // Simple pluralization/singularization for units
      const unitText = topic.intervalLength === 1
        ? topic.intervalUnit.replace(/s$/, '') // Remove trailing 's' if length is 1
        : topic.intervalUnit.endsWith('s') ? topic.intervalUnit : `${topic.intervalUnit}s`; // Add 's' if length > 1 and not already plural

      if(topic.intervalLength % 1440 == 0)
        {
          if(topic.intervalLength / 1440 == 1)
            return `${topic.numberOfIntervals} ${intervalText} of ${topic.intervalLength/1440} Day`;
          else
          return `${topic.numberOfIntervals} ${intervalText} of ${topic.intervalLength/1440} Days`;
        }
      else if(topic.intervalLength % 60 == 0)
        {
          if(topic.intervalLength / 60 == 1)
            return `${topic.numberOfIntervals} ${intervalText} of ${topic.intervalLength/60} Hour`;
          else
            return `${topic.numberOfIntervals} ${intervalText} of ${topic.intervalLength/60} Hours`;
        }
      return `${topic.numberOfIntervals} ${intervalText} of ${topic.intervalLength} ${unitText}`;
  };
