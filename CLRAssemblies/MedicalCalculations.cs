// ============================================
// CLR Assembly: MedicalCalculations
// Lakeview Medical Center
// C# CLR functions deployed to SQL Server
// Legacy: CLR assemblies require special handling
// during migration to Azure SQL MI
// ============================================

using System;
using System.Data;
using System.Data.SqlClient;
using System.Data.SqlTypes;
using System.Text.RegularExpressions;
using System.Collections;
using System.Collections.Generic;
using Microsoft.SqlServer.Server;

namespace LakeviewMedical.CLR
{
    /// <summary>
    /// CLR scalar and table-valued functions for medical calculations
    /// that are too complex for pure T-SQL implementation.
    /// 
    /// MIGRATION NOTE: CLR assemblies in Azure SQL MI require:
    /// - PERMISSION_SET = EXTERNAL_ACCESS or UNSAFE may need adjustment
    /// - Assembly must be signed or database must be marked TRUSTWORTHY
    /// - Some .NET Framework APIs may not be available
    /// </summary>
    public class MedicalCalculations
    {
        // ============================================
        // Drug Interaction Check
        // Checks for known drug-drug interactions
        // ============================================
        [SqlFunction(
            DataAccess = DataAccessKind.Read,
            SystemDataAccess = SystemDataAccessKind.Read,
            IsDeterministic = false,
            Name = "fn_CLR_CheckDrugInteractions")]
        public static SqlString CheckDrugInteractions(SqlString drugCode1, SqlString drugCode2)
        {
            if (drugCode1.IsNull || drugCode2.IsNull)
                return SqlString.Null;

            string drug1 = drugCode1.Value.ToUpper().Trim();
            string drug2 = drugCode2.Value.ToUpper().Trim();

            // Known interaction database (in production, this would query 
            // an external drug interaction database via linked server)
            var interactions = new Dictionary<string, Dictionary<string, string>>
            {
                { "WARFARIN", new Dictionary<string, string>
                    {
                        { "ASPIRIN", "MAJOR: Increased bleeding risk. Monitor INR closely." },
                        { "IBUPROFEN", "MAJOR: Increased bleeding risk. Avoid combination if possible." },
                        { "AMIODARONE", "MAJOR: Significantly increases warfarin levels. Reduce warfarin dose by 30-50%." },
                        { "FLUCONAZOLE", "MAJOR: Inhibits warfarin metabolism. Monitor INR." },
                        { "METRONIDAZOLE", "MAJOR: Inhibits warfarin metabolism. Consider dose reduction." }
                    }
                },
                { "METFORMIN", new Dictionary<string, string>
                    {
                        { "CONTRAST_DYE", "MAJOR: Risk of lactic acidosis. Hold metformin 48h before/after contrast." },
                        { "ALCOHOL", "MODERATE: Increased risk of lactic acidosis and hypoglycemia." }
                    }
                },
                { "LISINOPRIL", new Dictionary<string, string>
                    {
                        { "POTASSIUM", "MODERATE: Risk of hyperkalemia. Monitor potassium levels." },
                        { "SPIRONOLACTONE", "MODERATE: Additive hyperkalemia risk. Monitor electrolytes." },
                        { "NSAID", "MODERATE: NSAIDs may reduce ACE inhibitor efficacy and increase renal risk." }
                    }
                },
                { "SIMVASTATIN", new Dictionary<string, string>
                    {
                        { "AMIODARONE", "MAJOR: Increased risk of rhabdomyolysis. Limit simvastatin to 20mg." },
                        { "CLARITHROMYCIN", "MAJOR: Significantly increases statin levels. Suspend statin during therapy." },
                        { "GRAPEFRUIT", "MODERATE: Increases statin absorption. Avoid large quantities." }
                    }
                },
                { "DIGOXIN", new Dictionary<string, string>
                    {
                        { "AMIODARONE", "MAJOR: Increases digoxin levels by 70-100%. Reduce digoxin dose." },
                        { "VERAPAMIL", "MAJOR: Increases digoxin levels. Monitor levels closely." },
                        { "FUROSEMIDE", "MODERATE: Hypokalemia increases digoxin toxicity risk. Monitor K+." }
                    }
                }
            };

            // Check both directions
            string result = CheckInteractionPair(interactions, drug1, drug2);
            if (result == null)
                result = CheckInteractionPair(interactions, drug2, drug1);

            return result != null ? new SqlString(result) : new SqlString("NO_INTERACTION");
        }

        private static string CheckInteractionPair(
            Dictionary<string, Dictionary<string, string>> interactions, 
            string drug1, string drug2)
        {
            if (interactions.ContainsKey(drug1) && interactions[drug1].ContainsKey(drug2))
                return interactions[drug1][drug2];
            return null;
        }

        // ============================================
        // ICD-10 Code Validation (comprehensive)
        // Validates format and checks against known ranges
        // ============================================
        [SqlFunction(
            IsDeterministic = true,
            IsPrecise = true,
            Name = "fn_CLR_ValidateICDCode")]
        public static SqlBoolean ValidateICDCode(SqlString icdCode)
        {
            if (icdCode.IsNull || string.IsNullOrWhiteSpace(icdCode.Value))
                return SqlBoolean.False;

            string code = icdCode.Value.Trim().ToUpper();

            // ICD-10-CM format: [A-Z][0-9][0-9].[0-9A-Z]{0,4}
            // First character: A-Z (letter category)
            // Characters 2-3: digits
            // Character 4: decimal point (optional)
            // Characters 5-7: alphanumeric (optional, up to 4 after decimal)
            string pattern = @"^[A-Z]\d{2}(\.\d{1,4}[A-Z]?)?$";
            
            if (!Regex.IsMatch(code, pattern))
                return SqlBoolean.False;

            // Validate category ranges
            char category = code[0];
            int subcategory = int.Parse(code.Substring(1, 2));

            // Valid ICD-10-CM ranges
            switch (category)
            {
                case 'A': case 'B': // Infectious diseases (A00-B99)
                    return new SqlBoolean(true);
                case 'C': // Neoplasms (C00-C96)
                    return new SqlBoolean(subcategory <= 96);
                case 'D': // Blood diseases and neoplasms (D00-D89)
                    return new SqlBoolean(subcategory <= 89);
                case 'E': // Endocrine (E00-E89)
                    return new SqlBoolean(subcategory <= 89);
                case 'F': // Mental/behavioral (F01-F99)
                    return new SqlBoolean(subcategory >= 1);
                case 'G': // Nervous system (G00-G99)
                    return new SqlBoolean(true);
                case 'H': // Eye and ear (H00-H95)
                    return new SqlBoolean(subcategory <= 95);
                case 'I': // Circulatory (I00-I99)
                    return new SqlBoolean(true);
                case 'J': // Respiratory (J00-J99)
                    return new SqlBoolean(true);
                case 'K': // Digestive (K00-K95)
                    return new SqlBoolean(subcategory <= 95);
                case 'L': // Skin (L00-L99)
                    return new SqlBoolean(true);
                case 'M': // Musculoskeletal (M00-M99)
                    return new SqlBoolean(true);
                case 'N': // Genitourinary (N00-N99)
                    return new SqlBoolean(true);
                case 'O': // Pregnancy (O00-O9A)
                    return new SqlBoolean(true);
                case 'P': // Perinatal (P00-P96)
                    return new SqlBoolean(subcategory <= 96);
                case 'Q': // Congenital (Q00-Q99)
                    return new SqlBoolean(true);
                case 'R': // Symptoms (R00-R99)
                    return new SqlBoolean(true);
                case 'S': case 'T': // Injury (S00-T88)
                    return new SqlBoolean(category == 'S' || subcategory <= 88);
                case 'V': case 'W': case 'X': case 'Y': // External causes (V00-Y99)
                    return new SqlBoolean(true);
                case 'Z': // Factors influencing health (Z00-Z99)
                    return new SqlBoolean(true);
                default:
                    return SqlBoolean.False;
            }
        }

        // ============================================
        // BMI Category Classification
        // Returns WHO BMI classification
        // ============================================
        [SqlFunction(
            IsDeterministic = true,
            IsPrecise = true,
            Name = "fn_CLR_GetBMICategory")]
        public static SqlString GetBMICategory(SqlDouble bmi)
        {
            if (bmi.IsNull || bmi.Value <= 0)
                return SqlString.Null;

            double bmiValue = bmi.Value;

            if (bmiValue < 16.0) return new SqlString("Severe Thinness");
            if (bmiValue < 17.0) return new SqlString("Moderate Thinness");
            if (bmiValue < 18.5) return new SqlString("Mild Thinness");
            if (bmiValue < 25.0) return new SqlString("Normal");
            if (bmiValue < 30.0) return new SqlString("Overweight");
            if (bmiValue < 35.0) return new SqlString("Obese Class I");
            if (bmiValue < 40.0) return new SqlString("Obese Class II");
            return new SqlString("Obese Class III");
        }

        // ============================================
        // GFR Calculation (CKD-EPI equation)
        // Calculates estimated Glomerular Filtration Rate
        // ============================================
        [SqlFunction(
            IsDeterministic = true,
            IsPrecise = false,
            Name = "fn_CLR_CalculateGFR")]
        public static SqlDouble CalculateGFR(
            SqlDouble creatinine, SqlInt32 age, SqlBoolean isFemale, SqlBoolean isBlack)
        {
            if (creatinine.IsNull || age.IsNull || isFemale.IsNull || creatinine.Value <= 0)
                return SqlDouble.Null;

            double scr = creatinine.Value;
            int ageVal = age.Value;
            bool female = isFemale.Value;
            bool black = !isBlack.IsNull && isBlack.Value;

            double kappa = female ? 0.7 : 0.9;
            double alpha = female ? -0.329 : -0.411;
            double femaleFactor = female ? 1.018 : 1.0;
            double blackFactor = black ? 1.159 : 1.0;

            double minRatio = Math.Min(scr / kappa, 1.0);
            double maxRatio = Math.Max(scr / kappa, 1.0);

            double gfr = 141.0 
                * Math.Pow(minRatio, alpha) 
                * Math.Pow(maxRatio, -1.209) 
                * Math.Pow(0.993, ageVal) 
                * femaleFactor 
                * blackFactor;

            return new SqlDouble(Math.Round(gfr, 2));
        }

        // ============================================
        // Table-valued function: Parse HL7 Message Segments
        // Parses an HL7 v2.x message and returns segments
        // ============================================
        [SqlFunction(
            FillRowMethodName = "FillHL7SegmentRow",
            TableDefinition = "SegmentIndex int, SegmentType nvarchar(10), FieldCount int, RawSegment nvarchar(max)",
            Name = "fn_CLR_ParseHL7Segments")]
        public static IEnumerable ParseHL7Segments(SqlString hl7Message)
        {
            if (hl7Message.IsNull)
                yield break;

            string message = hl7Message.Value;
            string[] segments = message.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
            
            for (int i = 0; i < segments.Length; i++)
            {
                string segment = segments[i].Trim();
                if (segment.Length < 3) continue;

                string segType = segment.Length >= 3 ? segment.Substring(0, 3) : segment;
                char fieldSep = '|';
                int fieldCount = segment.Split(fieldSep).Length;

                yield return new HL7SegmentRow
                {
                    SegmentIndex = i,
                    SegmentType = segType,
                    FieldCount = fieldCount,
                    RawSegment = segment
                };
            }
        }

        public static void FillHL7SegmentRow(
            object row,
            out SqlInt32 segmentIndex,
            out SqlString segmentType,
            out SqlInt32 fieldCount,
            out SqlString rawSegment)
        {
            var seg = (HL7SegmentRow)row;
            segmentIndex = new SqlInt32(seg.SegmentIndex);
            segmentType = new SqlString(seg.SegmentType);
            fieldCount = new SqlInt32(seg.FieldCount);
            rawSegment = new SqlString(seg.RawSegment);
        }

        private class HL7SegmentRow
        {
            public int SegmentIndex;
            public string SegmentType;
            public int FieldCount;
            public string RawSegment;
        }

        // ============================================
        // Medication Name Normalization
        // Normalizes drug names for comparison
        // ============================================
        [SqlFunction(
            IsDeterministic = true,
            IsPrecise = true,
            Name = "fn_CLR_NormalizeDrugName")]
        public static SqlString NormalizeDrugName(SqlString drugName)
        {
            if (drugName.IsNull)
                return SqlString.Null;

            string name = drugName.Value.Trim().ToUpper();

            // Remove common suffixes
            string[] suffixes = { " HCL", " HYDROCHLORIDE", " SODIUM", " POTASSIUM", 
                                  " SULFATE", " ACETATE", " TARTRATE", " MALEATE",
                                  " MESYLATE", " BESYLATE", " FUMARATE" };
            
            foreach (var suffix in suffixes)
            {
                if (name.EndsWith(suffix))
                {
                    name = name.Substring(0, name.Length - suffix.Length);
                    break;
                }
            }

            // Remove dosage forms
            name = Regex.Replace(name, @"\s*(TABLET|CAPSULE|INJECTION|SOLUTION|SUSPENSION|CREAM|OINTMENT|PATCH|INHALER)\s*", " ");
            
            // Remove dosage amounts  
            name = Regex.Replace(name, @"\s*\d+\s*(MG|MCG|ML|G|%|UNITS?)\s*", " ");
            
            // Clean up whitespace
            name = Regex.Replace(name, @"\s+", " ").Trim();

            return new SqlString(name);
        }
    }
}
