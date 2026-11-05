import assert from 'node:assert/strict';
import {generateKeyPairSync, sign} from 'node:crypto';
import {test} from 'node:test';

import {amountInGrams, handleRequest, verifyFirebaseIdToken} from './index.js';

const projectId = 'fittrack-mydatabase';
const {privateKey, publicKey} = generateKeyPairSync('rsa', {modulusLength: 2048});
const publicJwk = publicKey.export({format: 'jwk'});
publicJwk.kid = 'test-key';
publicJwk.alg = 'RS256';

function makeToken(overrides = {}) {
  const now = Math.floor(Date.now() / 1000);
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const header = encode({alg: 'RS256', kid: 'test-key', typ: 'JWT'});
  const payload = encode({
    aud: projectId,
    iss: `https://securetoken.google.com/${projectId}`,
    sub: 'user-123',
    iat: now,
    exp: now + 3600,
    ...overrides,
  });
  const input = `${header}.${payload}`;
  return `${input}.${sign('RSA-SHA256', Buffer.from(input), privateKey).toString('base64url')}`;
}

function fakeFetch(url, init) {
  const target = String(url);
  if (target.includes('service_accounts/v1/jwk')) {
    return Promise.resolve(Response.json({keys: [publicJwk]}));
  }
  if (target.includes('/foods/search')) {
    const parsedUrl = new URL(target);
    assert.equal(parsedUrl.searchParams.get('api_key'), 'test-usda-key');
    assert.equal(parsedUrl.searchParams.get('pageSize'), '5');
    assert.equal(parsedUrl.searchParams.get('dataType'), 'Foundation,SR Legacy');
    const query = parsedUrl.searchParams.get('query');
    if (query === 'mango') {
      return Promise.resolve(Response.json({foods: []}));
    }
    if (query === 'raw spinach') {
      return Promise.resolve(Response.json({
        foods: [
          {
            fdcId: 456,
            description: 'Spinach, cooked, boiled, drained',
            dataType: 'SR Legacy',
          },
          {
            fdcId: 457,
            description: 'Spinach, raw',
            dataType: 'SR Legacy',
          },
        ],
      }));
    }
    return Promise.resolve(Response.json({
      foods: [
        {
          fdcId: 123,
          description: 'Rice and chicken ready meal',
          dataType: 'Branded',
          brandName: 'Example Brand',
        },
        {
          fdcId: 321,
          description: 'Rice, white, long-grain, regular, cooked',
          dataType: 'SR Legacy',
        },
      ],
    }));
  }
  if (target.includes('/food/')) {
    const parsedUrl = new URL(target);
    assert.equal(parsedUrl.searchParams.get('api_key'), 'test-usda-key');
    const fdcId = parsedUrl.pathname.split('/').pop();
    const macros = fdcId === '457'
      ? [23, 2.9, 3.6, 0.4]
      : [130, 2.7, 28, 0.3];
    return Promise.resolve(Response.json({
      fdcId: Number(fdcId),
      foodNutrients: [
        {nutrient: {id: 1008}, amount: macros[0]},
        {nutrient: {id: 1003}, amount: macros[1]},
        {nutrient: {id: 1005}, amount: macros[2]},
        {nutrient: {id: 1004}, amount: macros[3]},
      ],
    }));
  }
  if (target.includes('generateContent')) {
    assert.equal(
      target,
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent',
    );
    assert.equal(new Headers(init.headers).get('x-goog-api-key'), 'test-gemini-key');
    const request = JSON.parse(init.body);
    const prompt = request.contents[0].parts.map((part) => part.text ?? '').join('\n');
    if (prompt.includes('Compare this photo')) {
      return Promise.resolve(Response.json({
        candidates: [{content: {parts: [{text: '{"matches":true}'}]}}],
      }));
    }
    if (prompt.includes('Estimate nutrition per 100 grams')) {
      return Promise.resolve(Response.json({
        candidates: [{content: {parts: [{text: '{"items":[{"calories":60,"protein":1,"carbs":15,"fat":0.2}]}'}]}}],
      }));
    }
    return Promise.resolve(Response.json({
      candidates: [{content: {parts: [{text: '{"is_food":true,"meal_name":"Rice","meal_type":"Lunch","ingredients":[{"name":"cooked rice","amount":100,"unit":"g"}]}'}]}}],
    }));
  }
  throw new Error(`Unexpected request: ${target}`);
}

const env = {
  FIREBASE_PROJECT_ID: projectId,
  GEMINI_API_KEY: 'test-gemini-key',
  USDA_API_KEY: 'test-usda-key',
};

test('Firebase ID tokens are verified and expired tokens are rejected', async () => {
  const token = makeToken();
  assert.deepEqual(await verifyFirebaseIdToken(token, projectId, fakeFetch), {uid: 'user-123'});
  await assert.rejects(
    verifyFirebaseIdToken(makeToken({exp: 1}), projectId, fakeFetch),
    /invalid or expired/,
  );
});

test('food endpoint requires Firebase authentication', async () => {
  const response = await handleRequest(
    new Request('https://food.example.workers.dev/api/food', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({action: 'nutrition', ingredients: [{name: 'rice', amount: 100, unit: 'g'}]}),
    }),
    env,
    fakeFetch,
  );
  assert.equal(response.status, 401);
  assert.equal((await response.json()).error.code, 'unauthenticated');
});

test('scan endpoint sends a valid photo to Gemini and returns detected ingredients', async () => {
  const response = await handleRequest(
    new Request('https://food.example.workers.dev/api/food', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${makeToken()}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        action: 'scan',
        imageBase64: '/9j/2Q==',
        mimeType: 'image/jpeg',
      }),
    }),
    env,
    fakeFetch,
  );
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.is_food, true);
  assert.equal(result.ingredients[0].name, 'cooked rice');
});

test('nutrition uses a generic USDA detail record and scales values by grams', async () => {
  const response = await handleRequest(
    new Request('https://food.example.workers.dev/api/food', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${makeToken()}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        action: 'nutrition',
        ingredients: [{name: 'cooked rice', amount: 200, unit: 'g'}],
      }),
    }),
    env,
    fakeFetch,
  );
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.deepEqual(result.nutrition, {
    calories: 260,
    protein: 5.4,
    carbs: 56,
    fat: 0.6,
    has_ai_fallback: false,
  });
  assert.equal(result.ingredients[0].source, 'USDA FoodData Central');
});

test('nutrition prefers a raw record for raw ingredients', async () => {
  const response = await handleRequest(
    new Request('https://food.example.workers.dev/api/food', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${makeToken()}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        action: 'nutrition',
        ingredients: [{name: 'raw spinach', amount: 100, unit: 'g'}],
      }),
    }),
    env,
    fakeFetch,
  );
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.deepEqual(result.nutrition, {
    calories: 23,
    protein: 2.9,
    carbs: 3.6,
    fat: 0.4,
    has_ai_fallback: false,
  });
  assert.equal(result.ingredients[0].source, 'USDA FoodData Central');
});

test('match endpoint compares the edited ingredient list with its photo', async () => {
  const response = await handleRequest(
    new Request('https://food.example.workers.dev/api/food', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${makeToken()}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        action: 'match',
        imageBase64: '/9j/2Q==',
        mimeType: 'image/jpeg',
        ingredients: [{name: 'Rice', amount: 150, unit: 'g'}],
      }),
    }),
    env,
    fakeFetch,
  );
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {matches_photo: true});
});

test('nutrition uses Gemini only when USDA has no matching ingredient', async () => {
  const response = await handleRequest(
    new Request('https://food.example.workers.dev/api/food', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${makeToken()}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        action: 'nutrition',
        ingredients: [{name: 'mango', amount: 100, unit: 'g'}],
      }),
    }),
    env,
    fakeFetch,
  );
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.nutrition.has_ai_fallback, true);
  assert.equal(result.nutrition.calories, 60);
  assert.equal(result.ingredients[0].source, 'Gemini estimate');
});

test('nutrition endpoint rejects invalid ingredient amounts', async () => {
  const response = await handleRequest(
    new Request('https://food.example.workers.dev/api/food', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${makeToken()}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        action: 'nutrition',
        ingredients: [{name: 'rice', amount: -1, unit: 'g'}],
      }),
    }),
    env,
    fakeFetch,
  );
  assert.equal(response.status, 400);
  assert.equal((await response.json()).error.code, 'invalid-argument');
});

test('health endpoint and portion conversions are available', async () => {
  const response = await handleRequest(
    new Request('https://food.example.workers.dev/health'),
    env,
    fakeFetch,
  );
  assert.deepEqual(await response.json(), {status: 'ok'});
  assert.equal(amountInGrams({name: 'egg', amount: 2, unit: 'pcs'}), 100);
});
