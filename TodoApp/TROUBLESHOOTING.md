# Troubleshooting API Key Issues

If your OpenAI API key isn't working, here are the most common solutions:

## 🔍 Quick Checks

1. **API Key Format**
   - Must start with `sk-`
   - Should be about 51 characters long
   - No extra spaces or characters

2. **API Key Validity**
   - Make sure you copied the entire key
   - Check that your OpenAI account has credits
   - Verify the key hasn't been revoked

## 🛠️ Step-by-Step Debugging

### 1. Check Console Output
When you test the connection, check the Xcode console for detailed error messages:
- Look for lines starting with 🔑, 📤, 📥, ❌
- These will show exactly what's happening

### 2. Common Error Messages

**"Invalid API key" (401 error)**
- Your API key is incorrect or expired
- Solution: Generate a new key from OpenAI

**"Rate limit exceeded" (429 error)**
- You've made too many requests
- Solution: Wait a few minutes and try again

**"Network error"**
- Internet connection issue
- Solution: Check your internet connection

**"API request failed"**
- General server error
- Solution: Try again later

### 3. Manual Testing

You can test your API key manually using curl:

```bash
curl -X POST https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 10
  }'
```

Replace `YOUR_API_KEY_HERE` with your actual API key.

### 4. Getting a New API Key

1. Go to https://platform.openai.com/api-keys
2. Sign in to your OpenAI account
3. Click "Create new secret key"
4. Copy the entire key (starts with `sk-`)
5. Paste it in the app settings

### 5. Account Issues

- **No credits**: Add payment method to your OpenAI account
- **Account suspended**: Contact OpenAI support
- **Free tier limits**: Check your usage at https://platform.openai.com/usage

## 🐛 Still Having Issues?

1. **Check the console output** in Xcode for specific error messages
2. **Try the manual curl test** above
3. **Verify your OpenAI account** has credits
4. **Generate a fresh API key** and try again

## 📞 Getting Help

If you're still having issues:
1. Check the console output for specific error messages
2. Try the manual curl test to verify your key works
3. Make sure your OpenAI account has credits
4. Generate a new API key and try again

The app will show detailed error messages in the settings panel to help identify the specific issue. 