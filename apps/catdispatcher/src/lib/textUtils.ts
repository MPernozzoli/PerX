/**
 * Normalizes text to have first letter uppercase and rest lowercase
 * Handles multiple words by capitalizing each word
 */
export const normalizeText = (text: string | null | undefined): string => {
  if (!text) return '';
  
  return text
    .toLowerCase()
    .split(' ')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
};

/**
 * Map of Italian province codes to full names
 */
export const PROVINCE_MAP: Record<string, string> = {
  'AG': 'Agrigento',
  'AL': 'Alessandria',
  'AN': 'Ancona',
  'AO': 'Aosta',
  'AP': 'Ascoli Piceno',
  'AQ': "L'Aquila",
  'AR': 'Arezzo',
  'AT': 'Asti',
  'AV': 'Avellino',
  'BA': 'Bari',
  'BG': 'Bergamo',
  'BI': 'Biella',
  'BL': 'Belluno',
  'BN': 'Benevento',
  'BO': 'Bologna',
  'BR': 'Brindisi',
  'BS': 'Brescia',
  'BT': 'Barletta-Andria-Trani',
  'BZ': 'Bolzano',
  'CA': 'Cagliari',
  'CB': 'Campobasso',
  'CE': 'Caserta',
  'CH': 'Chieti',
  'CL': 'Caltanissetta',
  'CN': 'Cuneo',
  'CO': 'Como',
  'CR': 'Cremona',
  'CS': 'Cosenza',
  'CT': 'Catania',
  'CZ': 'Catanzaro',
  'EN': 'Enna',
  'FC': 'Forlì-Cesena',
  'FE': 'Ferrara',
  'FG': 'Foggia',
  'FI': 'Firenze',
  'FM': 'Fermo',
  'FR': 'Frosinone',
  'GE': 'Genova',
  'GO': 'Gorizia',
  'GR': 'Grosseto',
  'IM': 'Imperia',
  'IS': 'Isernia',
  'KR': 'Crotone',
  'LC': 'Lecco',
  'LE': 'Lecce',
  'LI': 'Livorno',
  'LO': 'Lodi',
  'LT': 'Latina',
  'LU': 'Lucca',
  'MB': 'Monza e della Brianza',
  'MC': 'Macerata',
  'ME': 'Messina',
  'MI': 'Milano',
  'MN': 'Mantova',
  'MO': 'Modena',
  'MS': 'Massa-Carrara',
  'MT': 'Matera',
  'NA': 'Napoli',
  'NO': 'Novara',
  'NU': 'Nuoro',
  'OR': 'Oristano',
  'PA': 'Palermo',
  'PC': 'Piacenza',
  'PD': 'Padova',
  'PE': 'Pescara',
  'PG': 'Perugia',
  'PI': 'Pisa',
  'PN': 'Pordenone',
  'PO': 'Prato',
  'PR': 'Parma',
  'PT': 'Pistoia',
  'PU': 'Pesaro e Urbino',
  'PV': 'Pavia',
  'PZ': 'Potenza',
  'RA': 'Ravenna',
  'RC': 'Reggio Calabria',
  'RE': 'Reggio Emilia',
  'RG': 'Ragusa',
  'RI': 'Rieti',
  'RM': 'Roma',
  'RN': 'Rimini',
  'RO': 'Rovigo',
  'SA': 'Salerno',
  'SI': 'Siena',
  'SO': 'Sondrio',
  'SP': 'La Spezia',
  'SR': 'Siracusa',
  'SS': 'Sassari',
  'SU': 'Sud Sardegna',
  'SV': 'Savona',
  'TA': 'Taranto',
  'TE': 'Teramo',
  'TN': 'Trento',
  'TO': 'Torino',
  'TP': 'Trapani',
  'TR': 'Terni',
  'TS': 'Trieste',
  'TV': 'Treviso',
  'UD': 'Udine',
  'VA': 'Varese',
  'VB': 'Verbano-Cusio-Ossola',
  'VC': 'Vercelli',
  'VE': 'Venezia',
  'VI': 'Vicenza',
  'VR': 'Verona',
  'VT': 'Viterbo',
  'VV': 'Vibo Valentia',
};

/**
 * Get full province name from province code
 */
export const getProvinceName = (provinciaCode: string | null | undefined): string => {
  if (!provinciaCode) return '';
  return PROVINCE_MAP[provinciaCode.toUpperCase()] || provinciaCode;
};

/**
 * Get province code from full name or validate existing code
 * Handles both cases: "Torino" → "TO" and "TO" → "TO"
 */
export const getProvinceCode = (provinciaName: string | null | undefined): string | null => {
  if (!provinciaName) return null;
  
  const trimmed = provinciaName.trim();
  const upper = trimmed.toUpperCase();
  
  // First check if it's already a valid province code (2-3 chars)
  if (trimmed.length <= 3 && PROVINCE_MAP[upper]) {
    return upper;
  }
  
  // Otherwise, search by full name
  const normalizedName = trimmed.toLowerCase();
  const entry = Object.entries(PROVINCE_MAP).find(
    ([_, name]) => name.toLowerCase() === normalizedName
  );
  
  return entry ? entry[0] : null;
};
