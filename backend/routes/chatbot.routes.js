import express from 'express';
import { protect } from '../middleware/auth.middleware.js';
import { sendMessage } from '../controllers/chatbot.controller.js';

const router = express.Router();

// All routes require authentication
router.use(protect);

router.post('/send-message', sendMessage);

export default router;
