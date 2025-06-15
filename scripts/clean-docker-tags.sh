#!/bin/bash

# Script to help manage Docker Hub tags for magicalyak/transmissionvpn
# This script helps identify unwanted tags that should be cleaned up

set -e

IMAGE_NAME="magicalyak/transmissionvpn"
DOCKER_HUB_API="https://hub.docker.com/v2/repositories/${IMAGE_NAME}/tags"

echo "🔍 Checking Docker Hub tags for ${IMAGE_NAME}..."
echo

# Function to get tags from Docker Hub API
get_docker_hub_tags() {
    local page_size=100
    local page=1
    local all_tags=()
    
    while true; do
        echo "📄 Fetching page ${page}..."
        
        # Get tags from Docker Hub API
        response=$(curl -s "${DOCKER_HUB_API}?page_size=${page_size}&page=${page}")
        
        # Check if we got a valid response
        if ! echo "$response" | jq -e '.results' > /dev/null 2>&1; then
            echo "❌ Failed to get tags from Docker Hub API"
            echo "Response: $response"
            exit 1
        fi
        
        # Extract tag names
        page_tags=$(echo "$response" | jq -r '.results[].name')
        
        if [ -z "$page_tags" ]; then
            break
        fi
        
        all_tags+=($page_tags)
        
        # Check if there are more pages
        next=$(echo "$response" | jq -r '.next')
        if [ "$next" = "null" ]; then
            break
        fi
        
        ((page++))
    done
    
    printf '%s\n' "${all_tags[@]}"
}

# Function to categorize tags
categorize_tags() {
    local tags=("$@")
    local release_tags=()
    local unwanted_tags=()
    
    for tag in "${tags[@]}"; do
        if [[ "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+-r[0-9]+$ ]] || \
           [[ "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
           [[ "$tag" == "latest" ]] || \
           [[ "$tag" == "stable" ]]; then
            release_tags+=("$tag")
        else
            unwanted_tags+=("$tag")
        fi
    done
    
    echo "✅ RELEASE TAGS (should keep):"
    printf '   %s\n' "${release_tags[@]}" | sort -V
    echo
    
    echo "🗑️  UNWANTED TAGS (candidates for cleanup):"
    if [ ${#unwanted_tags[@]} -eq 0 ]; then
        echo "   None found! 🎉"
    else
        printf '   %s\n' "${unwanted_tags[@]}" | sort
        echo
        echo "💡 These tags typically include:"
        echo "   - Branch-based tags (main, develop, main-abc123)"
        echo "   - PR tags (pr-123)"
        echo "   - Date-based tags (20240101)"
        echo "   - SHA-based tags (sha-abc123)"
    fi
    echo
}

# Function to show cleanup commands
show_cleanup_commands() {
    local unwanted_tags=("$@")
    
    if [ ${#unwanted_tags[@]} -eq 0 ]; then
        return
    fi
    
    echo "🧹 CLEANUP COMMANDS:"
    echo "   To delete unwanted tags, you can use the Docker Hub web interface"
    echo "   or use a tool like 'docker-hub-utils' or API calls."
    echo
    echo "   Example API calls (requires Docker Hub token):"
    for tag in "${unwanted_tags[@]}"; do
        echo "   curl -X DELETE -H \"Authorization: JWT \$DOCKER_HUB_TOKEN\" \\"
        echo "        \"https://hub.docker.com/v2/repositories/${IMAGE_NAME}/tags/${tag}/\""
    done
    echo
}

# Main execution
echo "🚀 Starting Docker Hub tag analysis..."
echo

# Check if required tools are available
if ! command -v curl &> /dev/null; then
    echo "❌ curl is required but not installed"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "❌ jq is required but not installed"
    echo "   Install with: brew install jq (macOS) or apt-get install jq (Ubuntu)"
    exit 1
fi

# Get all tags
echo "📡 Fetching tags from Docker Hub..."
all_tags=($(get_docker_hub_tags))

echo "📊 Found ${#all_tags[@]} total tags"
echo

# Categorize tags
categorize_tags "${all_tags[@]}"

# Extract unwanted tags for cleanup commands
unwanted_tags=()
for tag in "${all_tags[@]}"; do
    if ! [[ "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+-r[0-9]+$ ]] && \
       ! [[ "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && \
       [[ "$tag" != "latest" ]] && \
       [[ "$tag" != "stable" ]]; then
        unwanted_tags+=("$tag")
    fi
done

show_cleanup_commands "${unwanted_tags[@]}"

echo "✨ Analysis complete!"
echo
echo "📋 SUMMARY:"
echo "   - Total tags: ${#all_tags[@]}"
echo "   - Release tags: $((${#all_tags[@]} - ${#unwanted_tags[@]}))"
echo "   - Unwanted tags: ${#unwanted_tags[@]}"
echo
echo "🎯 NEXT STEPS:"
echo "   1. Review the unwanted tags above"
echo "   2. Use Docker Hub web interface to delete unwanted tags"
echo "   3. Future releases will only create clean version tags"
echo "   4. The updated GitHub Actions workflow prevents new unwanted tags" 