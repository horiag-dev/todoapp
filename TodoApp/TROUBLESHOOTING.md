# Troubleshooting API Key Issues

If your Anthropic API key isn't working, here are the most common solutions:

## Quick Checks

1. **API Key Format**
   - Must start with `sk-ant-`
   - No extra spaces or characters

2. **API Key Validity**
   - Make sure you copied the entire key
   - Check that your Anthropic account has credits
   - Verify the key hasn't been revoked

3. **Demo Mode**
   - Enter `demo` as the API key to use built-in keyword tagging (no network required)

## Step-by-Step Debugging

### 1. Check Console Output
When you test the connection, check the Xcode console for detailed error messages:
- Look for lines starting with 🔑, 📤, 📥, ❌
- These will show exactly what's happening

### 2. Common Error Messages

**"Invalid API key" (401 error)**
- Your API key is incorrect or expired
- Solution: Generate a new key from Anthropic

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
curl -X POST https://api.anthropic.com/v1/messages \
  -H "x-api-key: YOUR_API_KEY_HERE" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 10,
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

Replace `YOUR_API_KEY_HERE` with your actual API key.

### 4. Getting a New API Key

1. Go to https://console.anthropic.com/settings/keys
2. Sign in to your Anthropic account
3. Click "Create Key"
4. Copy the entire key (starts with `sk-ant-`)
5. Paste it in the app settings

### 5. Account Issues

- **No credits**: Add payment method to your Anthropic account
- **Account suspended**: Contact Anthropic support
- **Usage limits**: Check your usage at https://console.anthropic.com/settings/usage

## Still Having Issues?

1. **Check the console output** in Xcode for specific error messages
2. **Try the manual curl test** above
3. **Verify your Anthropic account** has credits
4. **Generate a fresh API key** and try again
5. **Try demo mode** — enter `demo` as the API key to verify the app works without network

## Getting Help

If you're still having issues, file an issue at the project's GitHub repository.

The app will show detailed error messages in the settings panel to help identify the specific issue.
