'use strict';

const crypto = require('node:crypto');
const {initializeApp} = require('firebase-admin/app');
const {FieldValue, getFirestore} = require('firebase-admin/firestore');
const {defineSecret} = require('firebase-functions/params');
const {HttpsError, onCall} = require('firebase-functions/v2/https');

initializeApp();
const db = getFirestore();
const groqApiKey = defineSecret('GROQ_API_KEY');
const usdaApiKey = defineSecret('USDA_API_KEY');
const validTypes = new Set(['Breakfast', 'Lunch', 'Snack', 'Dinner']);
const validUnits = new Set(['g', 'ml', 'pcs']);
const validImageTypes = new Set(['image/jpeg', 'image/png', 'image/webp']);
const imageLimitBytes = 2 * 1024 * 1024;
const groqModelName = process.env.GROQ_MODEL || 'qwen/qwen3.8-27b';
const Type = Object.freeze({
  OBJECT: 'OBJECT',
  ARRAY: 'ARRAY',
  BOOLEAN: 'BOOLEAN',
  STRING: 'STRING',
  NUMBER: 'NUMBER',
});
const macroIds = {calories: 1008, protein: 1003, carbs: 1005, fat: 1004};
const energyFallbackIds = [2047, 2048];

exports.scanMeal = onCall(
  {
    region: 'us-central1',
    timeoutSeconds: 120,
    memory: '512MiB',
    maxInstances: 10,
    secrets: [groqApiKey, usdaApiKey],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in to scan a meal.');
    }
    const data = request.data ?? {};
    const action = data.action;
    if (action === 'scan' || (data.imageBase64 && !action)) {
      const image = decodeImage(data.imageBase64, data.mimeType);
      return identifyMeal(image.bytes, image.mimeType);
    }
    if (action === 'nutrition' || (Array.isArray(data.ingredients) && !action)) {
      return calculateNutrition(validateIngredients(data.ingredients));
    }
    if (action === 'match') {
      const image = decodeImage(data.imageBase64, data.mimeType);
      const ingredients = validateIngredients(data.ingredients);
      return {
        matches_photo: await comparePhoto(
          image.bytes,
          image.mimeType,
          ingredients,
        ),
      };
    }
    throw new HttpsError('invalid-argument', 'Choose scan, nutrition, or match.');
  },
);

function decodeImage(encoded, mimeType = 'image/jpeg') {
  mimeType = mimeType ?? 'image/jpeg';
  if (typeof encoded !== 'string' || encoded.length === 0) {
    throw new HttpsError('invalid-argument', 'Choose a food photo to scan.');
  }
  if (!validImageTypes.has(mimeType)) {
    throw new HttpsError('invalid-argument', 'The photo format is not supported.');
  }
  const image = Buffer.from(encoded, 'base64');
  if (
    image.length === 0 ||
    image.length > imageLimitBytes ||
    image.toString('base64').replace(/=+$/, '') !== encoded.replace(/=+$/, '')
  ) {
    throw new HttpsError(
      'invalid-argument',
      'The compressed photo is too large or could not be read.',
    );
  }
  const isJpeg = image[0] === 0xff && image[1] === 0xd8;
  const isPng =
    image.length >= 8 &&
    image.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  const isWebp =
    image.length >= 12 &&
    image.toString('ascii', 0, 4) === 'RIFF' &&
    image.toString('ascii', 8, 12) === 'WEBP';
  if (
    (mimeType === 'image/jpeg' && !isJpeg) ||
    (mimeType === 'image/png' && !isPng) ||
    (mimeType === 'image/webp' && !isWebp)
  ) {
    throw new HttpsError(
      'invalid-argument',
      'The photo content does not match its format.',
    );
  }
  return {bytes: image, mimeType};
}

async function identifyMeal(image, mimeType) {
  const response = await generateJson(
    [
      {
        inline_data: {
          mime_type: mimeType,
          data: image.toString('base64'),
        },
      },
      {
        text:
          'Look at this photo of food. List the visible ingredients with an ' +
          'estimated amount. Include preparation in ingredient names when ' +
          'visible or inferable, such as "cooked white rice" or "raw tomato". ' +
          'Return only JSON matching the requested schema. ' +
          'Use a simple English name and amount as a number; unit must be g, ' +
          'ml, or pcs. Use grams for most items and pcs for countable items ' +
          'like eggs. Prefer fewer ingredients over guessing. If the photo ' +
          'is not food, set is_food to false and ingredients to [].',
      },
    ],
    {
      type: Type.OBJECT,
      properties: {
        is_food: {type: Type.BOOLEAN},
        meal_name: {type: Type.STRING},
        meal_type: {
          type: Type.STRING,
          enum: ['Breakfast', 'Lunch', 'Snack', 'Dinner'],
        },
        ingredients: {
          type: Type.ARRAY,
          items: {
            type: Type.OBJECT,
            properties: {
              name: {type: Type.STRING},
              amount: {type: Type.NUMBER},
              unit: {type: Type.STRING, enum: ['g', 'ml', 'pcs']},
            },
            required: ['name', 'amount', 'unit'],
          },
        },
      },
      required: ['is_food', 'meal_name', 'meal_type', 'ingredients'],
    },
  );
  if (typeof response.is_food !== 'boolean') {
    throw new HttpsError('data-loss', 'The scan result was incomplete. Try again.');
  }
  if (!response.is_food) {
    return {
      is_food: false,
      meal_name: '',
      meal_type: 'Lunch',
      ingredients: [],
    };
  }
  const ingredients = validateIngredients(response.ingredients);
  if (ingredients.length === 0) {
    throw new HttpsError('data-loss', 'No ingredients were recognized. Try again.');
  }
  const mealType = validTypes.has(response.meal_type) ? response.meal_type : 'Lunch';
  return {
    is_food: true,
    meal_name:
      typeof response.meal_name === 'string'
        ? response.meal_name.trim().slice(0, 100)
        : '',
    meal_type: mealType,
    ingredients,
  };
}

function validateIngredients(value) {
  if (!Array.isArray(value) || value.length === 0 || value.length > 30) {
    throw new HttpsError(
      'invalid-argument',
      'Add between 1 and 30 ingredients to calculate nutrition.',
    );
  }
  return value.map((item) => {
    const name = typeof item?.name === 'string' ? item.name.trim() : '';
    const amount = Number(item?.amount);
    const unit = item?.unit;
    if (
      !name ||
      name.length > 80 ||
      !Number.isFinite(amount) ||
      amount <= 0 ||
      amount > 10000 ||
      !validUnits.has(unit)
    ) {
      throw new HttpsError(
        'invalid-argument',
        'Each ingredient needs a name, positive amount, and g, ml, or pcs unit.',
      );
    }
    return {name, amount, unit};
  });
}

async function calculateNutrition(ingredients) {
  const resolved = await Promise.all(
    ingredients.map(async (ingredient) => {
      const cachedOrUsda = await findNutritionPer100g(ingredient.name);
      return {
        ...ingredient,
        grams: amountInGrams(ingredient),
        per100g: cachedOrUsda?.nutrition ?? null,
        source: cachedOrUsda?.source ?? 'AI estimate',
      };
    }),
  );
  const missing = resolved.filter((item) => item.per100g === null);
  if (missing.length > 0) {
    const fallback = await estimateMissingNutrition(missing);
    await Promise.all(
      missing.map(async (item) => {
        const nutrition = fallback.get(item.name);
        if (!nutrition) return;
        item.per100g = nutrition;
        await writeNutritionCache(item.name, nutrition, 'AI estimate');
      }),
    );
  }
  const totals = {calories: 0, protein: 0, carbs: 0, fat: 0};
  for (const ingredient of resolved) {
    if (!ingredient.per100g) {
      throw new HttpsError(
        'data-loss',
        `Nutrition could not be estimated for ${ingredient.name}.`,
      );
    }
    for (const key of Object.keys(totals)) {
      totals[key] +=
        ingredient.per100g[key] * (ingredient.grams / 100);
    }
  }
  return {
    nutrition: {
      calories: Math.round(totals.calories),
      protein: roundOne(totals.protein),
      carbs: roundOne(totals.carbs),
      fat: roundOne(totals.fat),
      has_ai_fallback: resolved.some((item) => item.source === 'AI estimate'),
    },
    ingredients: resolved.map(({name, amount, unit, source}) => ({
      name,
      amount,
      unit,
      source,
    })),
  };
}

async function findNutritionPer100g(name) {
  try {
    const cached = await nutritionCacheRef(name).get();
    if (cached.exists && isNutrition(cached.data())) {
      const data = cached.data();
      return {
        nutrition: pickNutrition(data),
        source: data.source === 'AI estimate'
          ? 'AI estimate'
          : 'USDA FoodData Central',
      };
    }
  } catch (error) {
    logNutritionCacheFailure('read', error);
  }

  let usda;
  try {
    usda = await findUsdaNutrition(name);
  } catch (error) {
    console.error('food_usda_lookup_failed_using_ai_fallback', {
      code: error?.code ?? null,
      message: error?.message ?? String(error),
    });
    return null;
  }
  if (!usda) return null;
  await writeNutritionCache(name, usda, 'USDA FoodData Central');
  return {nutrition: usda, source: 'USDA FoodData Central'};
}

async function findUsdaNutrition(name) {
  const url = new URL('https://api.nal.usda.gov/fdc/v1/foods/search');
  url.searchParams.set('query', name);
  url.searchParams.set('dataType', 'Foundation,SR Legacy');
  url.searchParams.set('pageSize', '5');
  url.searchParams.set('api_key', usdaApiKey.value());
  const body = await getJsonWithRetry(url, 'USDA FoodData Central');
  const food = selectUsdaFood(body.foods, name);
  if (!food || !Array.isArray(food.foodNutrients)) return null;
  const byId = new Map(
    food.foodNutrients.map((nutrient) => [
      Number(nutrient.nutrientId),
      Number(nutrient.value),
    ]),
  );
  const primaryEnergy = byId.get(macroIds.calories);
  const calories = primaryEnergy > 0
    ? primaryEnergy
    : energyFallbackIds.map((id) => byId.get(id)).find(Number.isFinite);
  const nutrition = {
    calories,
    protein: byId.get(macroIds.protein),
    carbs: byId.get(macroIds.carbs),
    fat: byId.get(macroIds.fat),
  };
  return isNutrition(nutrition) ? nutrition : null;
}

function selectUsdaFood(foods, ingredientName) {
  if (!Array.isArray(foods)) return null;
  const normalize = (value) => value.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
  const query = normalize(ingredientName);
  const queryTokens = new Set(query.split(/\s+/).filter(Boolean));
  return foods
    .filter((food) => Array.isArray(food.foodNutrients))
    .map((food) => {
      const description = normalize(food.description ?? '');
      const descriptionTokens = new Set(description.split(/\s+/).filter(Boolean));
      const overlap = [...queryTokens].filter((token) => descriptionTokens.has(token)).length;
      const score =
        (description === query ? 100 : 0) +
        (description.includes(query) || query.includes(description) ? 20 : 0) +
        overlap / Math.max(queryTokens.size, 1);
      return {food, score};
    })
    .sort((left, right) => right.score - left.score)[0]?.food ?? null;
}

async function writeNutritionCache(name, nutrition, source) {
  try {
    await nutritionCacheRef(name).set({
      ...nutrition,
      source,
      cachedAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    logNutritionCacheFailure('write', error);
  }
}

function logNutritionCacheFailure(operation, error) {
  console.error('food_nutrition_cache_error', {
    operation,
    message: error?.message ?? String(error),
  });
}

function nutritionCacheRef(name) {
  const cacheId = crypto
    .createHash('sha256')
    .update(name.trim().toLowerCase())
    .digest('hex');
  return db.collection('foodNutritionCache').doc(cacheId);
}

function pickNutrition(value) {
  return {
    calories: Number(value.calories),
    protein: Number(value.protein),
    carbs: Number(value.carbs),
    fat: Number(value.fat),
  };
}

async function getJsonWithRetry(url, provider = 'USDA FoodData Central') {
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      const response = await fetch(url, {
        signal: AbortSignal.timeout(15000),
      });
      if (response.ok) return await response.json();
      const responseBody = await response.text();
      logProviderFailure(provider, response.status, responseBody);
      if (response.status !== 429 && response.status < 500) {
        throw providerError(provider, response.status, responseBody);
      }
      if (attempt === 3) {
        throw providerError(provider, response.status, responseBody);
      }
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      if (attempt === 3) {
        console.error('food_provider_network_error', {
          provider,
          message: error?.message ?? String(error),
        });
        throw new HttpsError(
          'unavailable',
          'Nutrition data is temporarily unavailable. Try again.',
          {provider, networkError: error?.message ?? String(error)},
        );
      }
    }
    await delay(400 * 2 ** attempt);
  }
}

async function estimateMissingNutrition(ingredients) {
  const response = await generateJson(
    [
      {
        text:
          'Estimate nutrition per 100 grams for each food ingredient below. ' +
          'Return values for calories (kcal), protein, carbs, and fat (grams). ' +
          'Return only estimates for the listed names, in the same order. ' +
          'Foods:\n' +
          ingredients.map((item) => `- ${item.name}`).join('\n'),
      },
    ],
    {
      type: Type.OBJECT,
      properties: {
        items: {
          type: Type.ARRAY,
          items: {
            type: Type.OBJECT,
            properties: {
              calories: {type: Type.NUMBER},
              protein: {type: Type.NUMBER},
              carbs: {type: Type.NUMBER},
              fat: {type: Type.NUMBER},
            },
            required: ['calories', 'protein', 'carbs', 'fat'],
          },
        },
      },
      required: ['items'],
    },
  );
  if (!Array.isArray(response.items) || response.items.length !== ingredients.length) {
    throw new HttpsError(
      'data-loss',
      'AI could not estimate one or more ingredients. Try again.',
    );
  }
  return new Map(
    ingredients.map((ingredient, index) => {
      const nutrition = response.items[index];
      if (!isNutrition(nutrition)) {
        throw new HttpsError(
          'data-loss',
          `AI returned invalid nutrition for ${ingredient.name}.`,
        );
      }
      return [ingredient.name, nutrition];
    }),
  );
}

async function comparePhoto(image, mimeType, ingredients) {
  const response = await generateJson(
    [
      {
        inline_data: {
          mime_type: mimeType,
          data: image.toString('base64'),
        },
      },
      {
        text:
          'Does this food photo reasonably match the ingredient list? Ignore ' +
          'minor quantity differences and hidden seasonings. Return matches ' +
          'false only for a clear, meaningful mismatch. Ingredients:\n' +
          ingredients
            .map((item) => `- ${item.name}: ${item.amount} ${item.unit}`)
            .join('\n'),
      },
    ],
    {
      type: Type.OBJECT,
      properties: {matches: {type: Type.BOOLEAN}},
      required: ['matches'],
    },
  );
  if (typeof response.matches !== 'boolean') {
    throw new HttpsError('data-loss', 'The photo check was incomplete. Try again.');
  }
  return response.matches;
}

async function generateJson(parts, responseSchema) {
  const jsonSchema = toJsonSchema(responseSchema);
  const prompt = [
    ...parts.map((part) => part.text).filter((text) => typeof text === 'string'),
    `Reply with ONLY a JSON object that follows this JSON schema, with no extra text:\n${JSON.stringify(jsonSchema)}`,
  ].join('\n\n');
  const content = [
    {type: 'text', text: prompt},
    ...parts.flatMap((part) => {
      const image = part.inline_data;
      if (!image) return [];
      return [{
        type: 'image_url',
        image_url: {
          url: `data:${image.mime_type};base64,${image.data}`,
        },
      }];
    }),
  ];

  for (let attempt = 0; attempt < 4; attempt++) {
    let response;
    try {
      response = await requestGroq(content, true);
      let responseBody;
      if (!response.ok) responseBody = await response.text();
      if (
        !response.ok &&
        response.status === 400 &&
        /response.?format|json.?object|json mode/i.test(responseBody) &&
        content.some((part) => part.type === 'image_url')
      ) {
        logProviderFailure('Groq', response.status, responseBody);
        response = await requestGroq(content, false);
        if (!response.ok) responseBody = await response.text();
      }

      if (response.ok) {
        let payload;
        try {
          payload = await response.json();
        } catch {
          throw new HttpsError('data-loss', 'The AI returned invalid data. Try again.');
        }
        const choice = payload.choices?.[0];
        const text = extractMessageText(choice?.message?.content).trim();
        if (!text) {
          console.error('food_provider_empty_response', {
            provider: 'Groq',
            finishReason: choice?.finish_reason ?? null,
          });
          throw new HttpsError('data-loss', 'The AI returned an empty result. Try again.');
        }
        return parseJsonObject(text);
      }

      logProviderFailure('Groq', response.status, responseBody);
      if (response.status !== 429 && response.status < 500) {
        throw providerError('Groq', response.status, responseBody);
      }
      if (attempt === 3) throw providerError('Groq', response.status, responseBody);
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      if (attempt === 3) {
        console.error('food_provider_network_error', {
          provider: 'Groq',
          message: error?.message ?? String(error),
        });
        throw new HttpsError(
          'unavailable',
          'Food scanning is temporarily unavailable. Try again.',
        );
      }
    }
    await delay(400 * 2 ** attempt);
  }
}

async function requestGroq(content, includeResponseFormat) {
  let apiKey;
  try {
    apiKey = groqApiKey.value();
  } catch (error) {
    console.error('food_provider_configuration_error', {
      provider: 'Groq',
      message: error?.message ?? String(error),
    });
    throw new HttpsError(
      'failed-precondition',
      'Food scanning is not configured yet.',
    );
  }
  if (!apiKey) {
    throw new HttpsError(
      'failed-precondition',
      'Food scanning is not configured yet.',
    );
  }
  const body = {
    model: groqModelName,
    messages: [{role: 'user', content}],
    temperature: 0.1,
    max_tokens: 1024,
  };
  if (includeResponseFormat) body.response_format = {type: 'json_object'};
  return fetch('https://api.groq.com/openai/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(30000),
  });
}

function toJsonSchema(schema) {
  if (Array.isArray(schema)) return schema.map(toJsonSchema);
  if (!schema || typeof schema !== 'object') return schema;
  const typeNames = {
    OBJECT: 'object',
    ARRAY: 'array',
    BOOLEAN: 'boolean',
    STRING: 'string',
    NUMBER: 'number',
    INTEGER: 'integer',
  };
  return Object.fromEntries(
    Object.entries(schema).map(([key, value]) => {
      if (key === 'type' && typeof value === 'string') {
        return [key, typeNames[value.toUpperCase()] ?? value.toLowerCase()];
      }
      return [key, toJsonSchema(value)];
    }),
  );
}

function extractMessageText(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content
    .filter((part) => part?.type === 'text' && typeof part.text === 'string')
    .map((part) => part.text)
    .join('');
}

function parseJsonObject(text) {
  try {
    const parsed = JSON.parse(text);
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) return parsed;
  } catch {
    // Try extracting an object from surrounding model text below.
  }

  const start = text.indexOf('{');
  if (start >= 0) {
    let depth = 0;
    let inString = false;
    let escaped = false;
    for (let index = start; index < text.length; index++) {
      const character = text[index];
      if (inString) {
        if (escaped) escaped = false;
        else if (character === '\\') escaped = true;
        else if (character === '"') inString = false;
        continue;
      }
      if (character === '"') inString = true;
      else if (character === '{') depth++;
      else if (character === '}' && --depth === 0) {
        try {
          const parsed = JSON.parse(text.slice(start, index + 1));
          if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
            return parsed;
          }
        } catch {
          break;
        }
      }
    }
  }
  throw new HttpsError('data-loss', 'The AI returned an unreadable result. Try again.');
}

function logProviderFailure(provider, status, responseBody) {
  console.error('food_provider_http_error', {
    provider,
    httpStatus: status,
    responseBody,
  });
}

function providerError(provider, status, responseBody) {
  const rateLimited = status === 429;
  return new HttpsError(
    rateLimited ? 'resource-exhausted' : 'unavailable',
    rateLimited
      ? 'The food service is busy. Please try again in a moment.'
      : `${provider} request failed. Try again.`,
    {provider, httpStatus: status, responseBody},
  );
}

function isNutrition(value) {
  return (
    value &&
    ['calories', 'protein', 'carbs', 'fat'].every(
      (key) => Number.isFinite(Number(value[key])) && Number(value[key]) >= 0,
    )
  );
}

function amountInGrams(ingredient) {
  if (ingredient.unit === 'g') return ingredient.amount;
  if (ingredient.unit === 'ml') return ingredient.amount;
  const name = ingredient.name.toLowerCase();
  const weights = [
    [/egg/, 50],
    [/banana/, 118],
    [/apple/, 182],
    [/orange/, 131],
    [/tomato/, 123],
    [/avocado/, 150],
    [/onion/, 110],
    [/garlic/, 3],
    [/bread|slice/, 30],
  ];
  const match = weights.find(([pattern]) => pattern.test(name));
  return ingredient.amount * (match ? match[1] : 50);
}

function roundOne(value) {
  return Math.round(value * 10) / 10;
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

exports._test = {
  amountInGrams,
  comparePhoto,
  decodeImage,
  estimateMissingNutrition,
  findUsdaNutrition,
  generateJson,
  identifyMeal,
  isNutrition,
  parseJsonObject,
  selectUsdaFood,
  toJsonSchema,
  validateIngredients,
};
