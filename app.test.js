const request = require('supertest');

jest.mock('pg', () => {
    const mPool = {
        query: jest.fn().mockResolvedValue({ rows: [{ id: 1, name: 'Test Tool', quantity: 10 }] })
    };
    return { Pool: jest.fn(() => mPool) };
});

process.env.PORT = '8001';
const app = require('./app');

describe('Simple Inventory API Tests', () => {
    
    it('GET / should return HTML with route listing', async () => {
        const res = await request(app)
            .get('/')
            .set('Accept', 'text/html');
        expect(res.statusCode).toEqual(200);
        expect(res.text).toContain('Simple Inventory API');
    });

    it('GET /health/alive should return 200 OK', async () => {
        const res = await request(app).get('/health/alive');
        expect(res.statusCode).toEqual(200);
        expect(res.text).toEqual('OK');
    });

    it('GET /items should return item list', async () => {
        const res = await request(app)
            .get('/items')
            .set('Accept', 'application/json');
        expect(res.statusCode).toEqual(200);
        expect(Array.isArray(res.body)).toBeTruthy();
    });

    it('POST /items should validate input', async () => {
        const res = await request(app)
            .post('/items')
            .send({ name: '' });
        expect(res.statusCode).toEqual(400);
    });
});