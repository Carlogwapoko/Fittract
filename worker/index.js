const FIREBASE_JWKS_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';
const GEMINI_MODEL = 'gemini-2.5-flash';
const MAX_IMAGE_BYTES = 1024 * 1024;
const MAX_BODY_BYTES = 2 * 1024 * 1024;
const USDA_CACHE_TTL_MS = 30 * 60 * 1000;
const MAX_USDA_CACHE_ENTRIES = 256;
const VALID_TYPES = new Set(['Breakfast', 'Lunch', 'Snack', 'Dinner']);
const VALID_UNITS = new Set(['g', 'ml', 'pcs']);
const MACRO_IDS = {calories: 1008, protein: 1003, carbs: 1005, fat: 1004};
const usdaNutritionCache = new Map();

export default {
  fetch(request, env) {
    return handleRequest(request, env);
  },
};

export async function handleRequest(request, env, fetchImpl = fetch) {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Max-Age': '86400',
  };
  const respond = (body, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: {...corsHeaders, 'Content-Type': 'application/json'},
    });

  if (request.method === 'OPTIONS') {
    return new Response(null, {status: 204, headers: corsHeaders});
  }
  const pathname = new URL(request.url).pathname;
  if (request.method === 'GET' && pathname === '/health') {
    return respond({status: 'ok'});
  }
  if (
    request.method !== 'POST' ||
    (pathname !== '/' && pathname !== '/api/food')
  ) {
    return respond({error: {code: 'not-found', message: 'Endpoint not found.'}}, 404);
  }
  if (!env.FIREBASE_PROJECT_ID) {
    return respond({
      error: {code: 'configuration', message: 'Firebase authentication is not configured.'},
    }, 503);
  }
  if (!env.GEMINI_API_KEY || !env.USDA_API_KEY) {
    return respond({
      error: {code: 'configuration', message: 'Food services are not configured.'},
    }, 503);
  }

  try {
    const authorization = request.headers.get('Authorization') ?? '';
    const token = authorization.startsWith('Bearer ')
      ? authorization.slice('Bearer '.length).trim()
      : '';
    if (!token) {
      throw new ApiError(401, 'unauthenticated', 'Sign in to use food scanning.');
    }
    const user = await verifyFirebaseIdToken(
      token,
      env.FIREBASE_PROJECT_ID,
      fetchImpl,
    );
    const declaredLength = Number(request.headers.get('Content-Length') ?? 0);
    if (declaredLength > MAX_BODY_BYTES) {
      throw new ApiError(413, 'invalid-argument', 'The request is too large.');
    }
    const rawBody = await request.text();
    if (new TextEncoder().encode(rawBody).length > MAX_BODY_BYTES) {
      throw new ApiError(413, 'invalid-argument', 'The request is too large.');
    }
    let data;
    try {
      data = JSON.parse(rawBody);
    } catch {
      throw new ApiError(400, 'invalid-argument', 'The request body must be valid JSON.');
    }
    if (!data || typeof data !== 'object' || Array.isArray(data)) {
      throw new ApiError(400, 'invalid-argument', 'The request body must be an object.');
    }

    switch (data.action) {
      case 'scan': {
        const image = decodeImage(data.imageBase64, data.mimeType);
        return respond(await identifyMeal(image, env, fetchImpl));
      }
      case 'nutrition': {
        const ingredients = validateIngredients(data.ingredients);
        return respond(await calculateNutrition(ingredients, env, fetchImpl));
      }
      case 'match': {
        const image = decodeImage(data.imageBase64, data.mimeType);
        const ingredients = validateIngredients(data.ingredients);
        const result = await comparePhoto(image, ingredients, env, fetchImpl);
        return respond({matches_photo: result});
      }
      default:
        throw new ApiError(
          400,
          'invalid-argument',
          'Choose scan, nutrition, or match.',
        );
    }
  } catch (error) {
    if (error instanceof ApiError) {
      return respond({error: {code: error.code, message: error.message}}, error.status);
    }
    console.error('food_worker_request_failed', {
      message: error instanceof Error ? error.message : String(error),
    });
    return respond({
      error: {code: 'unavailable', message: 'Food services are temporarily unavailable. Try again.'},
    }, 502);
  }
}

export async function verifyFirebaseIdToken(token, projectId, fetchImpl = fetch) {
  if (typeof token !== 'string' || token.length > 8192) {
    throw new ApiError(401, 'unauthenticated', 'The sign-in token is invalid.');
  }
  const pieces = token.split('.');
  if (pieces.length !== 3 || !projectId) {
    throw new ApiError(401, 'unauthenticated', 'Sign in again to continue.');
  }
  let header;
  let claims;
  try {
    header = decodeJwtPart(pieces[0]);
    claims = decodeJwtPart(pieces[1]);
  } catch {
    throw new ApiError(401, 'unauthenticated', 'The sign-in token is invalid.');
  }
  const now = Math.floor(Date.now() / 1000);
  if (
    header.alg !== 'RS256' ||
    typeof header.kid !== 'string' ||
    claims.aud !== projectId ||
    claims.iss !== `https://securetoken.google.com/${projectId}` ||
    typeof claims.sub !== 'string' ||
    claims.sub.length === 0 ||
    claims.sub.length > 128 ||
    !Number.isFinite(claims.exp) ||
    claims.exp <= now ||
    !Number.isFinite(claims.iat) ||
    claims.iat > now + 60 ||
    (claims.nbf !== undefined && (!Number.isFinite(claims.nbf) || claims.nbf > now))
  ) {
    throw new ApiError(401, 'unauthenticated', 'The sign-in token is invalid or expired.');
  }

  let keySet;
  try {
    const response = await fetchImpl(FIREBASE_JWKS_URL, {
      cf: {cacheTtl: 3600, cacheEverything: true},
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) throw new Error(`Firebase key lookup returned ${response.status}.`);
    keySet = await response.json();
  } catch {
    throw new ApiError(503, 'unavailable', 'Could not verify your sign-in. Try again.');
  }
  const jwk = keySet.keys?.find((key) => key.kid === header.kid);
  if (!jwk) {
    throw new ApiError(401, 'unauthenticated', 'The sign-in token is invalid.');
  }
  try {
    const key = await crypto.subtle.importKey(
      'jwk',
      jwk,
      {name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256'},
      false,
      ['verify'],
    );
    const signingInput = new TextEncoder().encode(`${pieces[0]}.${pieces[1]}`);
    const signature = decodeBase64Url(pieces[2]);
    const valid = await crypto.subtle.verify(
      'RSASSA-PKCS1-v1_5',
      key,
      signature,
      signingInput,
    );
    if (!valid) throw new Error('Signature mismatch.');
  } catch {
    throw new ApiError(401, 'unauthenticated', 'The sign-in token is invalid.');
  }
  return {uid: claims.sub};
}

function decodeJwtPart(value) {
  return JSON.parse(new TextDecoder().decode(decodeBase64Url(value)));
}

function decodeBase64Url(value) {
  const base64 = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, '=');
  const binary = atob(padded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function encodeBase64(bytes) {
  let binary = '';
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(binary);
}

function decodeImage(encoded, mimeType = 'image/jpeg') {
  if (typeof encoded !== 'string' || encoded.length === 0) {
    throw new ApiError(400, 'invalid-argument', 'Choose a food photo to scan.');
  }
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(mimeType)) {
    throw new ApiError(400, 'invalid-argument', 'The photo format is not supported.');
  }
  let bytes;
  try {
    const binary = atob(encoded);
    bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
  } catch {
    throw new ApiError(400, 'invalid-argument', 'The photo could not be read.');
  }
  if (
    bytes.length === 0 ||
    bytes.length > MAX_IMAGE_BYTES ||
    encodeBase64(bytes) !== encoded
  ) {
    throw new ApiError(400, 'invalid-argument', 'The compressed photo is too large or could not be read.');
  }
  const jpeg = bytes[0] === 0xff && bytes[1] === 0xd8;
  const png =
    bytes.length >= 8 &&
    [137, 80, 78, 71, 13, 10, 26, 10].every((value, index) => bytes[index] === value);
  const webp =
    bytes.length >= 12 &&
    new TextDecoder().decode(bytes.slice(0, 4)) === 'RIFF' &&
    new TextDecoder().decode(bytes.slice(8, 12)) === 'WEBP';
  if (
    (mimeType === 'image/jpeg' && !jpeg) ||
    (mimeType === 'image/png' && !png) ||
    (mimeType === 'image/webp' && !webp)
  ) {
    throw new ApiError(400, 'invalid-argument', 'The photo content does not match its format.');
  }
  return {data: encoded, mimeType};
}

function validateIngredients(value) {
  if (!Array.isArray(value) || value.length === 0 || value.length > 30) {
    throw new ApiError(
      400,
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
      !VALID_UNITS.has(unit)
    ) {
      throw new ApiError(
        400,
        'invalid-argument',
        'Each ingredient needs a name, positive amount, and g, ml, or pcs unit.',
      );
    }
    return {name, amount, unit};
  });
}

async function identifyMeal(image, env, fetchImpl) {
  const response = await generateJson(
    [{
      inlineData: {mimeType: image.mimeType, data: image.data},
      text:
        'Identify visible ingredients in this food photo and estimate their amounts. ' +
        'Use simple English names, grams for most items and pcs for countable items. ' +
        'Prefer fewer ingredients over guessing. If this is not food, set is_food false ' +
        'and return an empty ingredients list. Return a short meal name and meal type.',
    }],
    {
      type: 'OBJECT',
      properties: {
        is_food: {type: 'BOOLEAN'},
        meal_name: {type: 'STRING'},
        meal_type: {type: 'STRING', enum: [...VALID_TYPES]},
        ingredients: {
          type: 'ARRAY',
          items: {
            type: 'OBJECT',
            properties: {
              name: {type: 'STRING'},
              amount: {type: 'NUMBER'},
              unit: {type: 'STRING', enum: [...VALID_UNITS]},
            },
            required: ['name', 'amount', 'unit'],
          },
        },
      },
      required: ['is_food', 'meal_name', 'meal_type', 'ingredients'],
    },
    env,
    fetchImpl,
  );
  if (typeof response.is_food !== 'boolean') {
    throw new ApiError(502, 'data-loss', 'The scan result was incomplete. Try again.');
  }
  if (!response.is_food) {
    return {is_food: false, meal_name: '', meal_type: 'Lunch', ingredients: []};
  }
  const ingredients = validateIngredients(response.ingredients);
  return {
    is_food: true,
    meal_name: typeof response.meal_name === 'string' ? response.meal_name.trim().slice(0, 100) : '',
    meal_type: VALID_TYPES.has(response.meal_type) ? response.meal_type : 'Lunch',
    ingredients,
  };
}

async function comparePhoto(image, ingredients, env, fetchImpl) {
  const response = await generateJson(
    [{
      inlineData: {mimeType: image.mimeType, data: image.data},
      text:
        'Compare this photo with the ingredient list entered by the user. Ignore minor ' +
        'quantity differences and hidden seasonings. Return matches false only for a ' +
        'clear, meaningful mismatch. Ingredients:\n' +
        ingredients.map((item) => `- ${item.name}: ${item.amount} ${item.unit}`).join('\n'),
    }],
    {
      type: 'OBJECT',
      properties: {matches: {type: 'BOOLEAN'}},
      required: ['matches'],
    },
    env,
    fetchImpl,
  );
  if (typeof response.matches !== 'boolean') {
    throw new ApiError(502, 'data-loss', 'The photo check was incomplete. Try again.');
  }
  return response.matches;
}

async function calculateNutrition(ingredients, env, fetchImpl) {
  const resolved = [];
  for (let start = 0; start < ingredients.length; start += 4) {
    const group = ingredients.slice(start, start + 4);
    resolved.push(...await Promise.all(group.map(async (ingredient) => {
      try {
        const nutrition = await findUsdaNutrition(ingredient.name, env, fetchImpl);
        return {
          ...ingredient,
          grams: amountInGrams(ingredient),
          per100g: nutrition,
          source: nutrition ? 'USDA FoodData Central' : null,
        };
      } catch (error) {
        console.error('food_usda_lookup_failed', {
          message: error instanceof Error ? error.message : String(error),
        });
        return {...ingredient, grams: amountInGrams(ingredient), per100g: null, source: null};
      }
    })));
  }
  const missing = resolved.filter((item) => item.per100g === null);
  if (missing.length) {
    const estimate = await estimateMissingNutrition(missing, env, fetchImpl);
    for (let index = 0; index < missing.length; index++) {
      missing[index].per100g = estimate[index];
      missing[index].source = 'Gemini estimate';
    }
  }

  const totals = {calories: 0, protein: 0, carbs: 0, fat: 0};
  for (const ingredient of resolved) {
    for (const key of Object.keys(totals)) {
      totals[key] += ingredient.per100g[key] * ingredient.grams / 100;
    }
  }
  return {
    nutrition: {
      calories: Math.round(totals.calories),
      protein: roundOne(totals.protein),
      carbs: roundOne(totals.carbs),
      fat: roundOne(totals.fat),
      has_ai_fallback: resolved.some((item) => item.source === 'Gemini estimate'),
    },
    ingredients: resolved.map(({name, amount, unit, source}) => ({
      name,
      amount,
      unit,
      source,
    })),
  };
}

async function findUsdaNutrition(name, env, fetchImpl) {
  const cacheKey = normalizeFoodName(name);
  const cached = usdaNutritionCache.get(cacheKey);
  if (cached && cached.expiresAt > Date.now()) return cached.nutrition;
  if (cached) usdaNutritionCache.delete(cacheKey);

  const url = new URL('https://api.nal.usda.gov/fdc/v1/foods/search');
  url.searchParams.set('query', name);
  url.searchParams.set('dataType', 'Foundation,SR Legacy');
  url.searchParams.set('pageSize', '5');
  url.searchParams.set('api_key', env.USDA_API_KEY);
  const response = await fetchWithTimeout(fetchImpl, url, {}, 15000);
  if (!response.ok) {
    throw new Error(`USDA FoodData Central returned HTTP ${response.status}.`);
  }
  const result = await response.json();
  const food = selectUsdaFood(result.foods, name);
  let nutrition = null;
  if (food && Number.isInteger(Number(food.fdcId)) && Number(food.fdcId) > 0) {
    const detailUrl = new URL(
      `https://api.nal.usda.gov/fdc/v1/food/${Number(food.fdcId)}`,
    );
    detailUrl.searchParams.set('api_key', env.USDA_API_KEY);
    const detailResponse = await fetchWithTimeout(fetchImpl, detailUrl, {}, 15000);
    if (!detailResponse.ok) {
      throw new Error(`USDA food detail returned HTTP ${detailResponse.status}.`);
    }
    const detail = await detailResponse.json();
    nutrition = readUsdaNutrition(detail.foodNutrients);
  }

  if (usdaNutritionCache.size >= MAX_USDA_CACHE_ENTRIES) {
    usdaNutritionCache.delete(usdaNutritionCache.keys().next().value);
  }
  usdaNutritionCache.set(cacheKey, {
    nutrition,
    expiresAt: Date.now() + USDA_CACHE_TTL_MS,
  });
  return nutrition;
}

function readUsdaNutrition(foodNutrients) {
  if (!Array.isArray(foodNutrients)) return null;
  const nutrients = new Map();
  for (const item of foodNutrients) {
    const id = Number(
      item.nutrient?.id ?? item.nutrientId ?? item.nutrientNumber,
    );
    const value = Number(item.amount ?? item.value);
    if (Number.isFinite(id) && Number.isFinite(value)) {
      nutrients.set(id, value);
    }
  }
  const calories =
    nutrients.get(MACRO_IDS.calories) ??
    nutrients.get(2047) ??
    nutrients.get(2048) ??
    (nutrients.has(1062) ? nutrients.get(1062) / 4.184 : undefined);
  const nutrition = {
    calories,
    protein: nutrients.get(MACRO_IDS.protein),
    carbs: nutrients.get(MACRO_IDS.carbs),
    fat: nutrients.get(MACRO_IDS.fat),
  };
  return isNutrition(nutrition) ? nutrition : null;
}

function selectUsdaFood(foods, ingredientName) {
  if (!Array.isArray(foods)) return null;
  const query = normalizeFoodName(ingredientName);
  if (!query) return null;
  const tokens = new Set(query.split(/\s+/).filter(Boolean));
  const preparationTerms = new Set([
    'baked', 'boiled', 'cooked', 'dried', 'fried', 'grilled', 'raw',
    'roasted', 'steamed',
  ]);
  const queryPreparation = [...tokens].find((token) =>
    preparationTerms.has(token),
  );
  const commonFoodTerms = new Set([
    'and', 'fresh', 'food', 'of', 'or', 'regular', 'with',
  ]);
  const best = foods
    .filter((food) => {
      const dataType = String(food.dataType ?? '').toLowerCase();
      return (
        Number.isInteger(Number(food.fdcId)) &&
        Number(food.fdcId) > 0 &&
        !dataType.includes('branded') &&
        !food.brandName &&
        !food.brandOwner
      );
    })
    .map((food) => {
      const description = normalizeFoodName(food.description ?? '');
      const descriptionTokens = new Set(description.split(/\s+/).filter(Boolean));
      const overlap = [...tokens].filter((token) => descriptionTokens.has(token)).length;
      const coreTokens = [...tokens].filter(
        (token) => !preparationTerms.has(token) && !commonFoodTerms.has(token),
      );
      const coreOverlap = coreTokens.filter((token) =>
        descriptionTokens.has(token),
      ).length;
      const unmatchedDescriptionTokens = [...descriptionTokens].filter(
        (token) =>
          !tokens.has(token) &&
          !commonFoodTerms.has(token) &&
          !preparationTerms.has(token),
      ).length;
      const descriptionPreparation = [...descriptionTokens].find((token) =>
        preparationTerms.has(token),
      );
      return {
        food,
        score:
          (description === query ? 1000 : 0) +
          (coreTokens.length > 0 && coreOverlap === coreTokens.length ? 100 : 0) +
          40 * (coreOverlap / Math.max(coreTokens.length, 1)) +
          (queryPreparation && descriptionPreparation === queryPreparation
            ? 24
            : queryPreparation && descriptionPreparation
              ? -24
              : 0) +
          overlap / Math.max(tokens.size, 1) -
          unmatchedDescriptionTokens * 2,
        coreCoverage: coreOverlap / Math.max(coreTokens.length, 1),
      };
    })
    .filter((candidate) => candidate.coreCoverage >= 0.5)
    .sort((left, right) => right.score - left.score)[0];
  return best ? best.food : null;
}

function normalizeFoodName(value) {
  return value.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
}

async function estimateMissingNutrition(ingredients, env, fetchImpl) {
  const response = await generateJson(
    [{
      text:
        'Estimate nutrition per 100 grams for these ingredients only. Return calories ' +
        'in kcal and protein, carbs, and fat in grams, in the same order. Foods:\n' +
        ingredients.map((item) => `- ${item.name}`).join('\n'),
    }],
    {
      type: 'OBJECT',
      properties: {
        items: {
          type: 'ARRAY',
          items: {
            type: 'OBJECT',
            properties: {
              calories: {type: 'NUMBER'},
              protein: {type: 'NUMBER'},
              carbs: {type: 'NUMBER'},
              fat: {type: 'NUMBER'},
            },
            required: ['calories', 'protein', 'carbs', 'fat'],
          },
        },
      },
      required: ['items'],
    },
    env,
    fetchImpl,
  );
  if (
    !Array.isArray(response.items) ||
    response.items.length !== ingredients.length ||
    !response.items.every(isNutrition)
  ) {
    throw new ApiError(502, 'data-loss', 'Nutrition could not be estimated for every ingredient.');
  }
  return response.items;
}

async function generateJson(parts, responseSchema, env, fetchImpl) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;
  const contentParts = parts.flatMap((part) => {
    const result = [];
    if (part.text) result.push({text: part.text});
    if (part.inlineData) result.push({inlineData: part.inlineData});
    return result;
  });
  const response = await fetchWithTimeout(fetchImpl, url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-goog-api-key': env.GEMINI_API_KEY,
    },
    body: JSON.stringify({
      contents: [{parts: contentParts}],
      generationConfig: {
        responseMimeType: 'application/json',
        responseSchema,
        temperature: 0.1,
      },
    }),
  }, 30000);
  if (!response.ok) {
    throw new ApiError(
      response.status === 429 ? 429 : 502,
      response.status === 429 ? 'resource-exhausted' : 'unavailable',
      response.status === 429
        ? 'The food service is busy right now. Try again in a moment.'
        : 'Gemini could not process this request. Try again.',
    );
  }
  let payload;
  try {
    payload = await response.json();
  } catch {
    throw new ApiError(502, 'data-loss', 'Gemini returned an invalid response.');
  }
  const text = payload.candidates?.[0]?.content?.parts
    ?.map((part) => part.text ?? '')
    .join('')
    .trim();
  if (!text) {
    throw new ApiError(502, 'data-loss', 'Gemini returned an empty response.');
  }
  try {
    const result = JSON.parse(text);
    if (!result || typeof result !== 'object' || Array.isArray(result)) throw new Error();
    return result;
  } catch {
    throw new ApiError(502, 'data-loss', 'Gemini returned unreadable data.');
  }
}

async function fetchWithTimeout(fetchImpl, input, init, timeoutMs) {
  try {
    return await fetchImpl(input, {
      ...init,
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch {
    throw new ApiError(502, 'unavailable', 'A food data provider could not be reached. Try again.');
  }
}

export function amountInGrams(ingredient) {
  if (ingredient.unit === 'g' || ingredient.unit === 'ml') return ingredient.amount;
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

function isNutrition(value) {
  return value &&
    ['calories', 'protein', 'carbs', 'fat'].every(
      (key) => Number.isFinite(Number(value[key])) && Number(value[key]) >= 0,
    );
}

function roundOne(value) {
  return Math.round(value * 10) / 10;
}

class ApiError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}
