import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import multer from 'multer';
import { GoogleGenAI } from '@google/genai'; // Let's use standard REST or @google/generative-ai
import { GoogleGenerativeAI } from '@google/generative-ai';

dotenv.config();

const app = express();
const port = process.env.PORT || 3001;

app.use(cors());
app.use(express.json());

// Set up multer for memory storage
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 } // 10MB limit
});

// Prompt and Schema for Gemini API
const systemInstruction = `
You are a receipt parsing assistant. You extract structured data from Ethiopian ERCA fiscal receipts. These receipts follow standard layout conventions: line items, followed by SUBTOTAL, then Service Chrg (Service Charge), then TXBL1 (Taxable Base), then TAX1 15% (VAT), and finally TOTAL.
Examine the image carefully and output a JSON object containing the parsed information.
Instructions:
1. Extract the merchant/restaurant name if visible.
2. For each line item, extract the description, quantity, unitPrice (unit price), and amount. If quantity or unit price is missing, calculate it (amount = quantity * unitPrice).
3. If an item is unreadable, return null for its properties or skip it. Do not invent line items.
4. Extract the exact subtotal, service charge amount (as printed, e.g. from 'Service Chrg' or similar line), taxRate (usually 0.15 for 15% VAT), taxAmount (VAT amount, usually printed as 'TAX1 15%' or 'TAX1' or 'VAT'), and total.
5. If some numbers are slightly blurry, make your best guess but if you cannot read a number, return null for it rather than inventing it.
`;

const responseSchema = {
  type: "object",
  properties: {
    merchantName: { type: "string", description: "Name of the restaurant/merchant" },
    subtotal: { type: "number", description: "The subtotal of all items before service charge and taxes" },
    serviceChargeAmount: { type: "number", description: "The absolute service charge amount (often 10% of subtotal, but printed as a number)" },
    taxRate: { type: "number", description: "The VAT rate, usually 0.15 (15%)" },
    taxAmount: { type: "number", description: "The VAT amount printed on the receipt" },
    total: { type: "number", description: "The absolute total amount printed on the receipt" },
    lineItems: {
      type: "array",
      items: {
        type: "object",
        properties: {
          description: { type: "string", description: "Description of the line item" },
          quantity: { type: "number", description: "Quantity of the item ordered" },
          unitPrice: { type: "number", description: "Price of a single unit of this item" },
          amount: { type: "number", description: "Total amount for this line item (quantity * unitPrice)" }
        },
        required: ["description", "quantity", "unitPrice", "amount"]
      }
    }
  },
  required: ["subtotal", "serviceChargeAmount", "taxRate", "taxAmount", "total", "lineItems"]
};

// Check if Gemini API key exists
const getApiKey = () => {
  return process.env.GEMINI_API_KEY;
};

app.post('/api/parse-receipt', upload.single('receipt'), async (req, res) => {
  try {
    const apiKey = getApiKey();
    if (!apiKey) {
      return res.status(401).json({
        error: "Missing API Key",
        message: "Gemini API key is not configured on the server. Please set the GEMINI_API_KEY environment variable in a .env file."
      });
    }

    if (!req.file) {
      return res.status(400).json({
        error: "No File Uploaded",
        message: "Please upload a receipt image."
      });
    }

    // Initialize Gemini API
    const genAI = new GoogleGenerativeAI(apiKey);
    
    // Use gemini-1.5-flash for OCR text extraction from images
    const model = genAI.getGenerativeModel({
      model: "gemini-1.5-flash",
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: responseSchema,
      }
    });

    // Convert buffer to generative part (base64)
    const imagePart = {
      inlineData: {
        data: req.file.buffer.toString("base64"),
        mimeType: req.file.mimetype
      },
    };

    const prompt = "Parse this receipt according to the schema instructions.";

    const result = await model.generateContent([
      prompt,
      imagePart,
      { text: `System Instructions: ${systemInstruction}` }
    ]);

    const response = await result.response;
    const text = response.text();

    try {
      const parsedData = JSON.parse(text);
      
      // Perform simple validation check
      // Do line items sum to subtotal?
      let computedSubtotal = 0;
      if (parsedData.lineItems) {
        computedSubtotal = parsedData.lineItems.reduce((acc, curr) => acc + (curr.amount || 0), 0);
      }
      
      // Is there a mismatch?
      const subtotalMismatch = Math.abs(computedSubtotal - parsedData.subtotal) > 1.0;
      const taxMismatch = Math.abs((parsedData.subtotal + parsedData.serviceChargeAmount) * parsedData.taxRate - parsedData.taxAmount) > 1.0;
      const totalMismatch = Math.abs(parsedData.subtotal + parsedData.serviceChargeAmount + parsedData.taxAmount - parsedData.total) > 1.0;

      const validation = {
        isValid: !subtotalMismatch && !taxMismatch && !totalMismatch,
        subtotalMismatch,
        taxMismatch,
        totalMismatch,
        computedSubtotal,
        message: ""
      };

      if (!validation.isValid) {
        validation.message = "Calculated subtotal or tax does not perfectly match the receipt totals. Please verify the entries.";
      }

      return res.json({
        success: true,
        data: parsedData,
        validation
      });

    } catch (e) {
      console.error("Failed to parse Gemini JSON output:", text, e);
      return res.status(500).json({
        error: "Parse Error",
        message: "Gemini returned JSON that could not be parsed or validated.",
        rawText: text
      });
    }

  } catch (error) {
    console.error("Gemini API Error:", error);
    return res.status(500).json({
      error: "Gemini API Error",
      message: error.message || "An error occurred while calling the Gemini Vision API."
    });
  }
});

app.listen(port, () => {
  console.log(`Fair Split backend proxy running at http://localhost:${port}`);
});
